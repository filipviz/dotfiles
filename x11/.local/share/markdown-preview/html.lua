function Pandoc(document)
  local has_html = false

  document:walk({
    RawBlock = function(element)
      has_html = has_html or element.format == "html"
    end,
    RawInline = function(element)
      has_html = has_html or element.format == "html"
    end,
  })

  if not has_html then
    return nil
  end

  local converted = pandoc.read(
    pandoc.write(document, "html", { html_math_method = "mathjax" }),
    "html+tex_math_single_backslash"
  )
  document.blocks = converted.blocks
  return document
end
