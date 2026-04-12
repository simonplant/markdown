use std::fs;
use std::io;

pub struct Document {
    content: String,
}

impl Document {
    pub fn open_file(path: &str) -> Result<Document, io::Error> {
        let content = fs::read_to_string(path)?;
        Ok(Document { content })
    }

    pub fn edit(&mut self, offset: usize, delete: usize, insert: &str) {
        let offset = offset.min(self.content.len());
        let end = (offset + delete).min(self.content.len());
        self.content.replace_range(offset..end, insert);
    }

    pub fn save_file(&self, path: &str) -> Result<(), io::Error> {
        fs::write(path, &self.content)
    }

    pub fn current_text(&self) -> &str {
        &self.content
    }
}
