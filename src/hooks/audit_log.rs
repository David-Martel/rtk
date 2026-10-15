//! Resolves the hook audit log consistently across platforms.

use std::ffi::OsString;
use std::path::PathBuf;

const AUDIT_LOG_FILE: &str = "hook-audit.log";

fn audit_dir_from(
    override_dir: Option<OsString>,
    home_dir: Option<PathBuf>,
    temp_dir: PathBuf,
) -> PathBuf {
    if let Some(dir) = override_dir.filter(|value| !value.is_empty()) {
        return PathBuf::from(dir);
    }

    home_dir
        .unwrap_or(temp_dir)
        .join(".local")
        .join("share")
        .join("rtk")
}

/// Returns the configured hook audit log path.
pub(crate) fn path() -> PathBuf {
    audit_dir_from(
        crate::core::user_dirs::env_path("RTK_AUDIT_DIR"),
        crate::core::user_dirs::home(),
        std::env::temp_dir(),
    )
    .join(AUDIT_LOG_FILE)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audit_override_uses_isolated_environment() {
        let dir = crate::core::test_isolation::root().join("audit-override");
        crate::core::user_env::with_path("RTK_AUDIT_DIR", Some(&dir), || {
            assert_eq!(path(), dir.join(AUDIT_LOG_FILE));
        });
    }

    #[test]
    fn override_directory_wins() {
        let dir = audit_dir_from(
            Some(OsString::from("C:\\rtk-audit")),
            Some(PathBuf::from("C:\\Users\\tester")),
            PathBuf::from("C:\\Temp"),
        );

        assert_eq!(dir, PathBuf::from("C:\\rtk-audit"));
    }

    #[test]
    fn home_directory_is_cross_platform_default() {
        let dir = audit_dir_from(
            None,
            Some(PathBuf::from("C:\\Users\\tester")),
            PathBuf::from("C:\\Temp"),
        );

        assert_eq!(
            dir,
            PathBuf::from("C:\\Users\\tester")
                .join(".local")
                .join("share")
                .join("rtk")
        );
    }

    #[test]
    fn temp_directory_is_last_resort() {
        let dir = audit_dir_from(None, None, PathBuf::from("C:\\Temp"));

        assert_eq!(
            dir,
            PathBuf::from("C:\\Temp")
                .join(".local")
                .join("share")
                .join("rtk")
        );
    }
}
