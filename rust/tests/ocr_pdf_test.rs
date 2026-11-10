use pdf_writer::types::TextRenderingMode;
use pdf_writer::{Content, Name, Pdf, Ref, Str};

#[test]
fn test_searchable_pdf_layer() {
    let mut pdf = Pdf::new();
    let font_ref = Ref::new(3);

    pdf.type1_font(font_ref).base_font(Name(b"Helvetica"));

    let mut content = Content::new();
    content.save_state();
    content.set_text_rendering_mode(TextRenderingMode::Invisible);
    content.begin_text();
    content.set_font(Name(b"F1"), 12.0);
    content.next_line(50.0, 700.0);
    content.show(Str(b"Invoice Number: 10492"));
    content.end_text();
    content.restore_state();

    assert!(!content.finish().is_empty());
}
