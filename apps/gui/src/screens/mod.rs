//! Wizard screens. Each module exposes `render(app, window, cx)` returning the
//! screen body; the root view (`WinMintApp`) routes to one based on the current
//! `WizardStep`. Add a step by adding a module here + a `WizardStep` variant.

pub mod build;
pub mod configure;
pub mod review;
pub mod source;
