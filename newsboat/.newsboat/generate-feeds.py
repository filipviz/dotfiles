#!/usr/bin/env python3
"""Generate local RSS feeds for sources that do not publish one."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from email.utils import format_datetime, parsedate_to_datetime
from html import unescape
from pathlib import Path
from typing import Callable
import fcntl
import hashlib
import json
import sys
import re
import time
from urllib.parse import urlparse
from urllib.request import Request, urlopen
import xml.etree.ElementTree as ET


ANTHROPIC_SITEMAP_URL = "https://www.anthropic.com/sitemap.xml"
OPENAI_RSS_URL = "https://openai.com/news/rss.xml"
BASE_DIR = Path(__file__).resolve().parent
OUTPUT_DIR = BASE_DIR / "generated"
CACHE_DIR = OUTPUT_DIR / "http-cache"
CACHE_TTL_SECONDS = 15 * 60
MAX_ITEMS = 300

ANTHROPIC_HOST = "www.anthropic.com"
ANTHROPIC_LISTING_PATHS = ("/news", "/research", "/engineering")
SAFETY_KEYWORDS = (
    "red-team",
    "red-teaming",
    "jailbreak",
    "safeguard",
    "misuse",
    "exploit",
    "cyber",
    "biosecurity",
    "responsible-scaling",
    "constitutional",
    "safety",
    "eval",
    "threat",
    "vulnerability",
)
OPENAI_MODEL_NAME_RE = re.compile(
    r"\b("
    r"gpt[- ]?(?:\d|oss|rosalind)|"
    r"openai\s+o\d|"
    r"o\d(?:[- ]mini|[- ]pro)?|"
    r"o4-mini|"
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


@dataclass(frozen=True)
class SitemapEntry:
    loc: str
    lastmod: datetime


@dataclass(frozen=True)
class PageMetadata:
    title: str
    published: datetime
    summary: str = ""


@dataclass(frozen=True)
class FeedItem:
    loc: str
    date: datetime
    title: str
    description: str
    categories: tuple[str, ...] = ()


@dataclass(frozen=True)
class FeedSpec:
    feed_id: str
    source: str
    filename: str
    title: str
    link: str
    description: str
    matcher: Callable[[FeedItem], bool]


def main(argv: list[str] | None = None) -> None:
    argv = sys.argv[1:] if argv is None else argv
    specs = feed_specs()

    if len(argv) == 1 and argv[0] in {spec.feed_id for spec in specs}:
        write_feed_to_stdout(argv[0], specs)
        return
    if (
        len(argv) == 2
        and argv[0] == "--feed"
        and argv[1] in {spec.feed_id for spec in specs}
    ):
        write_feed_to_stdout(argv[1], specs)
        return
    if argv:
        valid_feeds = ", ".join(spec.feed_id for spec in specs)
        raise SystemExit(
            f"usage: {Path(sys.argv[0]).name} [--feed FEED]\nfeeds: {valid_feeds}"
        )

    generate_feed_files(specs)


def generate_feed_files(specs: tuple[FeedSpec, ...]) -> None:
    items_by_source: dict[str, list[FeedItem]] = {}
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    for spec in specs:
        if spec.source not in items_by_source:
            items_by_source[spec.source] = fetch_items_for_source(spec.source)
        items = select_items(items_by_source[spec.source], spec)
        output_path = OUTPUT_DIR / spec.filename
        write_rss_file(spec, items, output_path)
        print(f"Wrote {len(items):3d} items to {output_path}")


def write_feed_to_stdout(feed_id: str, specs: tuple[FeedSpec, ...]) -> None:
    spec = next(spec for spec in specs if spec.feed_id == feed_id)
    entries = fetch_items_for_source(spec.source)
    items = select_items(entries, spec)
    write_rss_stream(spec, items, sys.stdout.buffer)


def feed_specs() -> tuple[FeedSpec, ...]:
    return (
        FeedSpec(
            "anthropic-research",
            "anthropic",
            "anthropic-research.xml",
            "Anthropic Research",
            "https://www.anthropic.com/research",
            "Anthropic research pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/research/"),
        ),
        FeedSpec(
            "anthropic-safety-red-team",
            "anthropic",
            "anthropic-safety-red-team.xml",
            "Anthropic Safety and Red Teaming",
            "https://www.anthropic.com/research",
            "Anthropic safety, misuse, eval, and red-team pages from the official sitemap.",
            is_safety_or_red_team,
        ),
        FeedSpec(
            "anthropic-news",
            "anthropic",
            "anthropic-news.xml",
            "Anthropic News",
            "https://www.anthropic.com/news",
            "Anthropic news pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/news/"),
        ),
        FeedSpec(
            "anthropic-engineering",
            "anthropic",
            "anthropic-engineering.xml",
            "Anthropic Engineering",
            "https://www.anthropic.com/engineering",
            "Anthropic engineering pages from the official sitemap.",
            lambda entry: has_path_prefix(entry.loc, "/engineering/"),
        ),
        FeedSpec(
            "openai-research-models",
            "openai",
            "openai-research-models.xml",
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
    metadata = fetch_anthropic_metadata()
    items: list[FeedItem] = []
    for entry in fetch_anthropic_sitemap():
        slug = urlparse(entry.loc).path.rstrip("/").rsplit("/", 1)[-1]
        page_metadata = metadata.get(entry.loc) or metadata.get(slug)
        if page_metadata:
            items.append(
                FeedItem(
                    loc=entry.loc,
                    date=page_metadata.published,
                    title=page_metadata.title,
                    description=page_metadata.summary
                    or f"Published {page_metadata.published.date().isoformat()}: {entry.loc}",
                )
            )
        else:
            items.append(
                FeedItem(
                    loc=entry.loc,
                    date=entry.lastmod,
                    title=title_from_url(entry.loc),
                    description=f"Updated {entry.lastmod.date().isoformat()}: {entry.loc}",
                )
            )
    return items


def fetch_anthropic_sitemap() -> list[SitemapEntry]:
    data = fetch_bytes(ANTHROPIC_SITEMAP_URL)
    root = ET.fromstring(data)
    entries: list[SitemapEntry] = []
    for url_node in root:
        loc = child_text(url_node, "loc")
        if not loc:
            continue
        lastmod = parse_lastmod(child_text(url_node, "lastmod"))
        entries.append(SitemapEntry(loc=loc, lastmod=lastmod))
    return entries


def fetch_anthropic_metadata() -> dict[str, PageMetadata]:
    metadata: dict[str, PageMetadata] = {}
    for path in ANTHROPIC_LISTING_PATHS:
        html = fetch_text(f"https://{ANTHROPIC_HOST}{path}")
        metadata.update(parse_anthropic_embedded_posts(html))
        if path == "/engineering":
            metadata.update(parse_anthropic_engineering_cards(html))
    return metadata


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
        r'<div[^>]*__date[^>]*>(?P<date>[^<]+)</div>',
        re.DOTALL,
    )
    for match in card_re.finditer(html):
        slug = unescape(match.group("slug"))
        loc = f"https://{ANTHROPIC_HOST}/engineering/{slug}"
        metadata[loc] = PageMetadata(
            title=strip_tags(match.group("title")),
            published=parse_display_date(match.group("date")),
        )
    return metadata


def fetch_openai_items() -> list[FeedItem]:
    root = ET.fromstring(fetch_bytes(OPENAI_RSS_URL))
    channel = root.find("channel")
    if channel is None:
        return []

    items: list[FeedItem] = []
    for item in channel.findall("item"):
        link = (item.findtext("link") or "").strip()
        title = (item.findtext("title") or link).strip()
        pub_date = parse_rss_date(item.findtext("pubDate"))
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
                description=description or f"Published {pub_date.date().isoformat()}: {link}",
                categories=categories,
            )
        )
    return items


def fetch_text(url: str) -> str:
    return fetch_bytes(url).decode("utf-8", "replace")


def fetch_bytes(url: str) -> bytes:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
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
        headers={"User-Agent": "newsboat-local-feed-generator/1.0"},
    )
    with urlopen(request, timeout=30) as response:
        return response.read()


def child_text(node: ET.Element, name: str) -> str:
    for child in node:
        if child.tag.rsplit("}", 1)[-1] == name:
            return (child.text or "").strip()
    return ""


def parse_lastmod(value: str) -> datetime:
    if not value:
        return datetime.now(UTC)
    if value.endswith("Z"):
        value = f"{value[:-1]}+00:00"
    return datetime.fromisoformat(value).astimezone(UTC)


def parse_display_date(value: str) -> datetime:
    return datetime.strptime(unescape(value).strip(), "%b %d, %Y").replace(tzinfo=UTC)


def parse_rss_date(value: str | None) -> datetime:
    if not value:
        return datetime.now(UTC)
    return parsedate_to_datetime(value).astimezone(UTC)


def decode_escaped_json_string(value: str) -> str:
    return json.loads(f'"{value}"')


def strip_tags(value: str) -> str:
    return unescape(re.sub(r"<[^>]+>", "", value)).strip()


def has_path_prefix(loc: str, prefix: str) -> bool:
    parsed = urlparse(loc)
    return parsed.netloc == ANTHROPIC_HOST and parsed.path.startswith(prefix)


def is_safety_or_red_team(entry: FeedItem) -> bool:
    parsed = urlparse(entry.loc)
    if parsed.netloc != ANTHROPIC_HOST:
        return False
    path = parsed.path.lower()
    if not (
        path.startswith("/research/")
        or path.startswith("/news/")
        or path.startswith("/engineering/")
    ):
        return False
    return any(keyword in path for keyword in SAFETY_KEYWORDS)


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
        return loc
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


def write_rss_file(spec: FeedSpec, items: list[FeedItem], output_path: Path) -> None:
    tree = rss_tree(spec, items)
    tmp_path = output_path.with_suffix(f"{output_path.suffix}.tmp")
    tree.write(tmp_path, encoding="utf-8", xml_declaration=True)
    tmp_path.replace(output_path)


def write_rss_stream(spec: FeedSpec, items: list[FeedItem], stream: object) -> None:
    tree = rss_tree(spec, items)
    tree.write(stream, encoding="utf-8", xml_declaration=True)


def add_text(parent: ET.Element, name: str, text: str) -> ET.Element:
    child = ET.SubElement(parent, name)
    child.text = text
    return child


if __name__ == "__main__":
    main()
