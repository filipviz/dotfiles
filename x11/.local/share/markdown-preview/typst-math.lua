function Math(element)
  -- Pandoc expands TeX's negative thin space to an overlapping -1em in Typst.
  element.text = element.text:gsub("\\!", "")
  return element
end
