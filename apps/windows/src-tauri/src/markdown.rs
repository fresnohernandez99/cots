//! Note bodies to HTML. Raw HTML in a note is shown as text, never run: notes are
//! written by agents, and the window can open files and links.

use pulldown_cmark::{html, CowStr, Event, Options, Parser};

pub fn render(markdown: &str) -> String {
    let options = Options::ENABLE_TABLES
        | Options::ENABLE_TASKLISTS
        | Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_FOOTNOTES;
    // 1-based line of each byte offset, so every task box knows which line it ticks.
    let line_starts: Vec<usize> = std::iter::once(0)
        .chain(markdown.match_indices('\n').map(|(i, _)| i + 1))
        .collect();
    let line_of = |offset: usize| line_starts.partition_point(|&start| start <= offset);

    let events = Parser::new_ext(markdown, options).into_offset_iter().map(|(event, range)| match event {
        Event::Html(text) | Event::InlineHtml(text) => Event::Text(text),
        // The window checks a task by its line (`cots check --line`), never by its text,
        // which can repeat or render differently from the source.
        Event::TaskListMarker(checked) => Event::InlineHtml(CowStr::from(format!(
            "<input type=\"checkbox\" data-line=\"{}\"{}> ",
            line_of(range.start),
            if checked { " checked disabled" } else { "" }
        ))),
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
        let html = render("hola <script>alert(1)</script> <img src=x onerror=alert(1)>");
        assert!(!html.contains("<script>"));
        assert!(!html.contains("<img"));
        assert!(html.contains("&lt;script&gt;"));
    }

    #[test]
    fn task_boxes_carry_their_line() {
        let html = render("# Pasos\n\n- [ ] uno\n- [x] dos\n  - [ ] tres");
        assert!(html.contains("data-line=\"3\""));
        assert!(html.contains("data-line=\"4\" checked disabled"));
        assert!(html.contains("data-line=\"5\""));
    }
}
