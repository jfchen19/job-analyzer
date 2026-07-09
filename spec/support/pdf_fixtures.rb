require "prawn"

# Deterministic in-memory PDF bytes for specs — no committed binaries.
module PdfFixtures
  # A PDF with selectable text.
  # NOTE: keep the text ASCII — Prawn's built-in Helvetica cannot encode CJK
  # (it raises Prawn::Errors::IncompatibleStringEncoding). Language doesn't
  # matter for testing extraction, so ASCII fixtures avoid embedding a CJK font.
  def pdf_with_text(str = "Ruby on Rails backend engineer 5 years")
    Prawn::Document.new do
      text str
    end.render
  end

  # A PDF with no text layer (blank page) — stands in for a scanned/image-only PDF.
  def blank_pdf
    Prawn::Document.new { |_pdf| }.render
  end

  # A PDF with large vertical gaps between blocks, so pdf-reader emits runs of
  # blank lines — used to verify #normalize collapses them.
  def pdf_with_gaps
    Prawn::Document.new do
      text "John Doe"
      move_down 40
      text "EXPERIENCE"
      move_down 50
      text "SKILLS"
    end.render
  end
end
