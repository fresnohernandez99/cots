//! Note bodies to HTML. Raw HTML in a note is shown as text, never run: notes are
//! written by agents, and the window can open files and links.

use pulldown_cmark::{html, Event, Options, Parser};

pub fn render(markdown: &str) -> String {
    let options = Options::ENABLE_TABLES
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_FOOTNOTES;
    let events = Parser::new_ext(markdown, options).map(|event| match event {
        Event::Html(text) | Event::InlineHtml(text) => Event::Text(text),
        other => other,
    });
    let mut out = String::with_capacity(markdown.len() * 3 / 2);
    html::push_html(&mut out, events);
    out
}

#[cfg(test)]
mod tests {
    use super::render;

    #[test]
    fn escapes_raw_html() {
        let html = render("hola <script>alert(1)</script>");
        assert!(!html.contains("<script>"));
        assert!(html.contains("&lt;script&gt;"));
    }

    #[test]
    fn renders_tasks() {
        let html = render("- [ ] uno\n- [x] dos");
        assert_eq!(html.matches("type=\"checkbox\"").count(), 2);
        assert!(html.contains("checked"));
    }
}
