function Math(element)
  -- Pandoc expands TeX's negative thin space to an overlapping -1em in Typst.
  element.text = element.text:gsub("\\!", "")

  -- Pandoc's standalone Typst writer can concatenate the transpose symbol with
  -- the upright(...) generated for an adjacent \mathbf, yielding the invalid
  -- Typst identifier "topupright". An empty TeX group preserves the token
  -- boundary without changing the expression's TeX meaning.
  element.text = element.text:gsub(
    "\\top(%s*)\\mathbf",
    "\\top{}%1\\mathbf"
  )

  -- Work around jgm/texmath#291: a one-character subscript followed by
  -- \rangle can be emitted as one invalid Typst identifier (for example,
  -- "_ichevron.r"). The empty group preserves the missing token boundary.
  element.text = element.text:gsub(
    "(_[%w])(%s*)\\rangle",
    "%1{}%2\\rangle"
  )

  return element
end
