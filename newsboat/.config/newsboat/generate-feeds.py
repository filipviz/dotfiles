#!/usr/bin/env python3
"""Generate local RSS feeds for sources that do not publish one."""

import fcntl
import gzip
import hashlib
import json
import re
import sys
import time
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import format_datetime, parsedate_to_datetime
from html import unescape
from pathlib import Path
from typing import BinaryIO, Callable
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ANTHROPIC_SITEMAP_URL = "https://www.anthropic.com/sitemap.xml"
OPENAI_RSS_URL = "https://openai.com/news/rss.xml"
BASE_DIR = Path(__file__).resolve().parent
CACHE_DIR = BASE_DIR / "generated" / "http-cache"
CACHE_TTL_SECONDS = 15 * 60
MAX_ITEMS = 300

ANTHROPIC_HOST = "www.anthropic.com"
ANTHROPIC_LISTING_PATHS = ("/news", "/research", "/engineering")
ANTHROPIC_ARTICLE_PATH_PREFIXES = tuple(f"{path}/" for path in ANTHROPIC_LISTING_PATHS)
OPENAI_MODEL_NAME_RE = re.compile(
    r"\b("
    r"gpt[- ]?(?:\d|oss|rosalind)|"
    r"openai\s+o\d|"
    r"o\d(?:[- ]mini|[- ]pro)?|"
    r"sora|"
    r"dall[- ]?e|"
    r"whisper|"
    r"audio models?|"
    r"image models?|"
    r"voice intelligence"
    r")\b",
    re.IGNORECASE,
)
OPENAI_MODEL_RELEASE_RE = re.compile(
    r"\b("
    r"introducing|previewing|releasing|launching|announcing|"
    r"new|next-generation|advancing|upgrades?"
    r")\b",
    re.IGNORECASE,
)
OPENAI_MODEL_RELEASE_CATEGORIES = {"Product", "Release", "API"}


@dataclass(frozen=True, slots=True)
class SitemapEntry:
    loc: str
    lastmod: datetime


@dataclass(frozen=True, slots=True)
class PageMetadata:
    title: str
    published: datetime
    summary: str = ""


@dataclass(frozen=True, slots=True)
class FeedItem:
    loc: str
    date: datetime
    title: str
    description: str
    categories: tuple[str, ...] = ()


@dataclass(frozen=True, slots=True)
class FeedSpec:
    feed_id: str
    source: str
    title: str
    link: str
    description: str
    matcher: Callable[[FeedItem], bool]


def main() -> None:
    argv = sys.argv[1:]
    specs = feed_specs()

    if len(argv) == 1 and argv[0] in {spec.feed_id for spec in specs}:
        write_feed_to_stdout(argv[0], specs)
        return

    valid_feeds = ", ".join(spec.feed_id for spec in specs)
    raise SystemExit(f"usage: {Path(sys.argv[0]).name} FEED\nfeeds: {valid_feeds}")


def write_feed_to_stdout(feed_id: str, specs: tuple[FeedSpec, ...]) -> None:
    spec = next(spec for spec in specs if spec.feed_id == feed_id)
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    entries = fetch_items_for_source(spec.source)
    items = select_items(entries, spec)
    if not items:
        raise ValueError(f"no items matched feed {feed_id}")
    write_rss_stream(spec, items, sys.stdout.buffer)


def feed_specs() -> tuple[FeedSpec, ...]:
    return (
        FeedSpec(
            "anthropic-research",
            "anthropic",
            "Anthropic Research",
            "https://www.anthropic.com/research",
            "Anthropic research pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/research/"),
        ),
        FeedSpec(
            "anthropic-news",
            "anthropic",
            "Anthropic News",
            "https://www.anthropic.com/news",
            "Anthropic news pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/news/"),
        ),
        FeedSpec(
            "anthropic-engineering",
            "anthropic",
            "Anthropic Engineering",
            "https://www.anthropic.com/engineering",
            "Anthropic engineering pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/engineering/"),
        ),
        FeedSpec(
            "openai-research-models",
            "openai",
            "OpenAI Research and Model Releases",
            "https://openai.com/news/",
            "OpenAI research posts and model-release posts from the official RSS feed.",
            is_openai_research_or_model_release,
        ),
    )


def fetch_items_for_source(source: str) -> list[FeedItem]:
    if source == "anthropic":
        return fetch_anthropic_items()
    if source == "openai":
        return fetch_openai_items()
    raise ValueError(f"unknown source: {source}")


def fetch_anthropic_items() -> list[FeedItem]:
    with ThreadPoolExecutor(max_workers=1 + len(ANTHROPIC_LISTING_PATHS)) as pool:
        entries_future = pool.submit(fetch_anthropic_sitemap)
        pages = list(
            pool.map(
                fetch_text,
                (f"https://{ANTHROPIC_HOST}{path}" for path in ANTHROPIC_LISTING_PATHS),
            )
        )
        entries = entries_future.result()

    metadata: dict[str, PageMetadata] = {}
    for path, html in zip(ANTHROPIC_LISTING_PATHS, pages):
        if path == "/engineering":
            metadata.update(parse_anthropic_engineering_cards(html))
        else:
            metadata.update(parse_anthropic_embedded_posts(html))

    items: list[FeedItem] = []
    for entry in entries:
        parsed_url = urlparse(entry.loc)
        if parsed_url.netloc != ANTHROPIC_HOST or not parsed_url.path.startswith(
            ANTHROPIC_ARTICLE_PATH_PREFIXES
        ):
            continue
        slug = parsed_url.path.rstrip("/").rsplit("/", 1)[-1]
        page_metadata = metadata.get(entry.loc) or metadata.get(slug)
        if page_metadata:
            items.append(
                FeedItem(
                    loc=entry.loc,
                    date=page_metadata.published,
                    title=page_metadata.title,
                    description=page_metadata.summary,
                )
            )
        else:
            items.append(
                FeedItem(
                    loc=entry.loc,
                    date=entry.lastmod,
                    title=title_from_url(entry.loc),
                    description="",
                )
            )
    return items


def fetch_anthropic_sitemap() -> list[SitemapEntry]:
    data = fetch_bytes(ANTHROPIC_SITEMAP_URL)
    root = ET.fromstring(data)
    entries: list[SitemapEntry] = []
    for url_node in root:
        loc = required_text(url_node, "{*}loc")
        lastmod = parse_lastmod(required_text(url_node, "{*}lastmod"))
        entries.append(SitemapEntry(loc=loc, lastmod=lastmod))
    if not entries:
        raise ValueError("Anthropic sitemap contains no entries")
    return entries


def parse_anthropic_embedded_posts(html: str) -> dict[str, PageMetadata]:
    metadata: dict[str, PageMetadata] = {}
    for chunk in html.split(r"\"_type\":\"post\"")[1:]:
        published_match = re.search(r'\\"publishedOn\\":\\"([^\\"]+)\\"', chunk)
        slug_match = re.search(
            r'\\"slug\\":\{\\"_type\\":\\"slug\\",\\"current\\":\\"([^\\"]+)\\"',
            chunk,
        )
        title_matches = list(
            re.finditer(r'\\"title\\":\\"((?:\\\\.|[^\\"])*)\\"', chunk)
        )
        if not (published_match and slug_match and title_matches):
            continue
        slug = slug_match.group(1)
        summary = parse_anthropic_summary(chunk)
        metadata[slug] = PageMetadata(
            title=decode_escaped_json_string(title_matches[-1].group(1)),
            published=parse_lastmod(published_match.group(1)),
            summary=summary,
        )
    if not metadata:
        raise ValueError("Anthropic page contains no embedded posts")
    return metadata


def parse_anthropic_summary(chunk: str) -> str:
    summary_match = re.search(
        r'\\"summary\\":(null|\\"((?:\\\\.|[^\\"])*)\\")',
        chunk,
    )
    if not summary_match or summary_match.group(1) == "null":
        return ""
    return decode_escaped_json_string(summary_match.group(2))


def parse_anthropic_engineering_cards(html: str) -> dict[str, PageMetadata]:
    metadata: dict[str, PageMetadata] = {}
    card_re = re.compile(
        r'href="/engineering/(?P<slug>[^"]+)".*?'
        r"<h3[^>]*>(?P<title>.*?)</h3>.*?"
        r"<div[^>]*__date[^>]*>(?P<date>[^<]+)</div>",
        re.DOTALL,
    )
    for match in card_re.finditer(html):
        slug = unescape(match.group("slug"))
        loc = f"https://{ANTHROPIC_HOST}/engineering/{slug}"
        metadata[loc] = PageMetadata(
            title=strip_tags(match.group("title")),
            published=parse_display_date(match.group("date")),
        )
    if not metadata:
        raise ValueError("Anthropic engineering page contains no article cards")
    return metadata


def fetch_openai_items() -> list[FeedItem]:
    root = ET.fromstring(fetch_bytes(OPENAI_RSS_URL))
    channel = root.find("channel")
    if channel is None:
        raise ValueError("OpenAI RSS feed has no channel")

    items: list[FeedItem] = []
    for item in channel.findall("item"):
        link = required_text(item, "link")
        title = required_text(item, "title")
        pub_date = parse_rss_date(required_text(item, "pubDate"))
        description = (item.findtext("description") or "").strip()
        categories = tuple(
            category.strip()
            for category in (node.text or "" for node in item.findall("category"))
            if category.strip()
        )
        items.append(
            FeedItem(
                loc=link,
                date=pub_date,
                title=title,
                description=description,
                categories=categories,
            )
        )
    if not items:
        raise ValueError("OpenAI RSS feed contains no items")
    return items


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode()


def fetch_bytes(url: str) -> bytes:
    cache_key = hashlib.sha256(url.encode("utf-8")).hexdigest()
    cache_path = CACHE_DIR / f"{cache_key}.body"
    lock_path = CACHE_DIR / f"{cache_key}.lock"

    with lock_path.open("w") as lock_file:
        fcntl.flock(lock_file, fcntl.LOCK_EX)
        cached = read_fresh_cache(cache_path)
        if cached is not None:
            return cached

        try:
            data = fetch_uncached_bytes(url)
        except Exception:
            if cache_path.exists():
                return cache_path.read_bytes()
            raise

        tmp_path = cache_path.with_suffix(".body.tmp")
        tmp_path.write_bytes(data)
        tmp_path.replace(cache_path)
        return data


def read_fresh_cache(cache_path: Path) -> bytes | None:
    if not cache_path.exists():
        return None
    age = time.time() - cache_path.stat().st_mtime
    if age > CACHE_TTL_SECONDS:
        return None
    return cache_path.read_bytes()


def fetch_uncached_bytes(url: str) -> bytes:
    request = Request(
        url,
        headers={
            "User-Agent": "newsboat-local-feed-generator/1.0",
            "Accept-Encoding": "gzip",
        },
    )
    with urlopen(request, timeout=30) as response:
        data = response.read()
    if response.headers.get("Content-Encoding", "").lower() == "gzip":
        data = gzip.decompress(data)
    return data


def parse_lastmod(value: str) -> datetime:
    return datetime.fromisoformat(value).astimezone(UTC)


def parse_display_date(value: str) -> datetime:
    return datetime.strptime(unescape(value).strip(), "%b %d, %Y").replace(tzinfo=UTC)


def parse_rss_date(value: str) -> datetime:
    return parsedate_to_datetime(value).astimezone(UTC)


def required_text(element: ET.Element, name: str) -> str:
    value = (element.findtext(name) or "").strip()
    if not value:
        raise ValueError(f"missing required {name} element")
    return value


def decode_escaped_json_string(value: str) -> str:
    return json.loads(f'"{value}"')


def strip_tags(value: str) -> str:
    return unescape(re.sub(r"<[^>]+>", "", value)).strip()


def has_path_prefix(loc: str, prefix: str) -> bool:
    parsed = urlparse(loc)
    return parsed.netloc == ANTHROPIC_HOST and parsed.path.startswith(prefix)


def is_openai_research_or_model_release(item: FeedItem) -> bool:
    categories = set(item.categories)
    if "Research" in categories:
        return True
    if not categories.intersection(OPENAI_MODEL_RELEASE_CATEGORIES):
        return False

    text = f"{item.title} {item.loc}"
    if "codex" in text.lower():
        return False
    if not OPENAI_MODEL_NAME_RE.search(text):
        return False
    if item.title.lower().startswith(("gpt", "openai o", "o3", "o4", "o5", "sora")):
        return True
    return OPENAI_MODEL_RELEASE_RE.search(text) is not None


def select_items(entries: list[FeedItem], spec: FeedSpec) -> list[FeedItem]:
    return sorted(
        (entry for entry in entries if spec.matcher(entry)),
        key=lambda entry: entry.date,
        reverse=True,
    )[:MAX_ITEMS]


def title_from_url(loc: str) -> str:
    path = urlparse(loc).path.rstrip("/")
    slug = path.rsplit("/", 1)[-1]
    if not slug:
        raise ValueError(f"URL has no title slug: {loc}")
    words = slug.replace("_", "-").split("-")
    return " ".join(format_title_word(word) for word in words if word)


def format_title_word(word: str) -> str:
    if word.isupper():
        return word
    if word.lower() in {"ai", "api", "asl", "mcp", "nist", "sb53"}:
        return word.upper()
    return word[:1].upper() + word[1:]


def rss_tree(spec: FeedSpec, items: list[FeedItem]) -> ET.ElementTree:
    now = datetime.now(UTC)
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    add_text(channel, "title", spec.title)
    add_text(channel, "link", spec.link)
    add_text(channel, "description", spec.description)
    add_text(channel, "lastBuildDate", format_datetime(now, usegmt=True))

    for entry in items:
        item = ET.SubElement(channel, "item")
        add_text(item, "title", entry.title)
        add_text(item, "link", entry.loc)
        guid = add_text(item, "guid", entry.loc)
        guid.set("isPermaLink", "true")
        add_text(item, "pubDate", format_datetime(entry.date, usegmt=True))
        add_text(item, "description", entry.description)
        for category in entry.categories:
            add_text(item, "category", category)

    tree = ET.ElementTree(rss)
    ET.indent(tree, space="  ")
    return tree


def write_rss_stream(spec: FeedSpec, items: list[FeedItem], stream: BinaryIO) -> None:
    tree = rss_tree(spec, items)
    tree.write(stream, encoding="utf-8", xml_declaration=True)


def add_text(parent: ET.Element, name: str, text: str) -> ET.Element:
    child = ET.SubElement(parent, name)
    child.text = text
    return child


if __name__ == "__main__":
    main()
