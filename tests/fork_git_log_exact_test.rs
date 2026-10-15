//! Native output comparisons for the fork's exact-format history contract.

mod common;

#[test]
fn explicit_formats_and_history_selectors_preserve_native_output() {
    let repo = common::temp_git_repo();
    for n in 0..60 {
        let result = common::native_command("git")
            .current_dir(repo.path())
            .args([
                "-c",
                "user.name=Fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "--allow-empty",
                "-m",
                &format!("history {n} caf\u{e9}"),
            ])
            .output()
            .expect("create history");
        assert!(result.status.success(), "{:?}", result);
    }
    for args in [
        vec!["log", "--format=%H"],
        vec!["log", "--pretty=format:%H|%s"],
        vec!["log", "--oneline"],
        vec!["log", "--all"],
        vec!["log", "HEAD~59..HEAD"],
        vec!["log", "--format=%H", "--max-count=3"],
        vec!["log", "--format=%H", "--max-count=0"],
        vec!["log", "--format=%H", "missing-revision"],
        vec![
            "-c",
            "i18n.logOutputEncoding=ISO-8859-1",
            "log",
            "--format=%B",
        ],
    ] {
        let native = common::native_command("git")
            .current_dir(repo.path())
            .args(&args)
            .output()
            .expect("native log");
        let mut command = common::rtk_command();
        common::suppress_hook_reminder(&mut command);
        let wrapped = command
            .current_dir(repo.path())
            .arg("git")
            .args(&args)
            .output()
            .expect("rtk log");
        if args.contains(&"i18n.logOutputEncoding=ISO-8859-1") {
            assert!(
                native.stdout.contains(&0xe9),
                "fixture must emit non-UTF-8 bytes"
            );
            assert!(std::str::from_utf8(&native.stdout).is_err());
        }
        assert_eq!(wrapped.status.code(), native.status.code(), "{args:?}");
        assert_eq!(wrapped.stdout, native.stdout, "{args:?}");
        assert_eq!(wrapped.stderr, native.stderr, "{args:?}");
    }
}
