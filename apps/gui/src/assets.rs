//! Asset loading: the GPUI `AssetSource` and brand-logo decoding.
//!
//! Separated from the view so image/IO concerns stay out of `Render` paths.

use std::borrow::Cow;
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;

use gpui::{AssetSource, Image, ImageFormat, SharedString};

/// Filesystem-backed asset source rooted at a base directory.
pub struct Assets {
    pub base: PathBuf,
}

impl AssetSource for Assets {
    fn load(&self, path: &str) -> gpui::Result<Option<Cow<'static, [u8]>>> {
        fs::read(self.base.join(path))
            .map(|data| Some(Cow::Owned(data)))
            .map_err(Into::into)
    }

    fn list(&self, path: &str) -> gpui::Result<Vec<SharedString>> {
        fs::read_dir(self.base.join(path))
            .map(|entries| {
                entries
                    .filter_map(|entry| {
                        entry
                            .ok()
                            .and_then(|entry| entry.file_name().into_string().ok())
                            .map(SharedString::from)
                    })
                    .collect()
            })
            .map_err(Into::into)
    }
}

/// Load the first decodable brand logo from `candidates`, falling back to an
/// empty image so the view always has something to render.
pub fn load_brand_logo(candidates: &[PathBuf]) -> Arc<Image> {
    for path in candidates {
        match fs::read(path) {
            Ok(bytes) => {
                eprintln!("WinMint GUI loaded brand logo: {}", path.display());
                return Arc::new(Image::from_bytes(ImageFormat::Png, bytes));
            }
            Err(err) => {
                eprintln!(
                    "WinMint GUI could not load brand logo '{}': {err}",
                    path.display()
                );
            }
        }
    }
    Arc::new(Image::empty())
}
