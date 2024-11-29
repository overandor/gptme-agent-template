#!/usr/bin/env python3
"""Pre-commit hook to verify file symlinks in state-based directories.

Features:
- Validates that each file in <type>/all/ has exactly one symlink in a state directory
- Verifies symlink integrity
- Handles special cases (like no-active-task.md)
- Self-contained with built-in tests (run with pytest)

Usage:
    Directly:
        python3 scripts/check_task_links.py [--type {tasks,tweets}]

    With pytest:
        pytest scripts/check_task_links.py

    As pre-commit hook (.pre-commit-config.yaml):
        - repo: local
          hooks:
          - id: check-task-links
            name: Check task/tweet symlinks
            entry: python3 scripts/check_task_links.py
            language: system
            pass_filenames: false
            always_run: true

Supported Types:
    tasks:
        State Directories:
            - tasks/new/: New tasks
            - tasks/active/: Active tasks
            - tasks/paused/: Paused tasks
            - tasks/done/: Completed tasks
            - tasks/cancelled/: Cancelled tasks
        Special Cases:
            - no-active-task.md: Should not have any symlinks
            - CURRENT_TASK.md: Should be a valid symlink

    tweets:
        State Directories:
            - tweets/new/: New tweets
            - tweets/queued/: Tweets awaiting review
            - tweets/approved/: Tweets ready to post
            - tweets/posted/: Published tweets

Error Reporting:
    Reports issues in format:
    - Missing link: file.md not linked in any state directory
    - Multiple links: file.md linked in multiple states: new, active
    - Invalid link: broken symlink in <type>/<state>/file.md
"""

import argparse
import os
import sys
import tempfile
from collections.abc import Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


def find_repo_root(start_path: Path) -> Path:
    """Find the repository root by looking for .git directory."""
    current = start_path.resolve()
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    return start_path.resolve()


@dataclass
class DirectoryConfig:
    """Configuration for a directory type."""

    type_name: str
    states: list[str]
    special_files: list[str]
    current_file: Optional[str] = None


CONFIGS = {
    "tasks": DirectoryConfig(
        type_name="tasks",
        states=["new", "active", "paused", "done", "cancelled"],
        special_files=["no-active-task.md"],
        current_file="CURRENT_TASK.md",
    ),
    "tweets": DirectoryConfig(
        type_name="tweets",
        states=["new", "queued", "approved", "posted"],
        special_files=[],
    ),
}


def get_state_dirs(repo_root: Path, config: DirectoryConfig) -> list[Path]:
    """Get all state directories for a given type."""
    return [repo_root / config.type_name / state for state in config.states]


def find_file_links(file: Path, state_dirs: list[Path]) -> list[Path]:
    """Find all symlinks pointing to a file."""
    links = []
    for state_dir in state_dirs:
        for link in state_dir.glob("*.md"):
            if link.is_symlink() and link.resolve() == file.resolve():
                links.append(link)
    return links


def verify_current_file(repo_root: Path, config: DirectoryConfig) -> list[str]:
    """Verify current file symlink if configured."""
    errors: list[str] = []

    if not config.current_file:
        return errors

    current_file = repo_root / config.current_file

    if not current_file.exists():
        errors.append(f"{config.current_file} does not exist")
        return errors

    if not current_file.is_symlink():
        errors.append(f"{config.current_file} is not a symlink")
        return errors

    try:
        target = current_file.resolve()
        if not target.exists():
            errors.append(
                f"{config.current_file} points to non-existent file: {target}"
            )
        elif not str(target).startswith(str(repo_root / config.type_name / "all/")):
            errors.append(
                f"{config.current_file} points outside {config.type_name}/all/: {target}"
            )
    except Exception as e:
        errors.append(f"Error resolving {config.current_file}: {e}")

    return errors


def verify_links(repo_root: Path | None = None, type_name: str = "tasks") -> list[str]:
    """Verify all files have exactly one valid symlink in a state directory."""
    if repo_root is None:
        repo_root = find_repo_root(Path.cwd())

    if type_name not in CONFIGS:
        return [f"Unknown type: {type_name}"]

    config = CONFIGS[type_name]
    errors = []

    # Get all state directories
    state_dirs = get_state_dirs(repo_root, config)
    files_dir = repo_root / config.type_name / "all"

    # Verify current file if configured
    if config.current_file:
        errors.extend(verify_current_file(repo_root, config))

    # Check each file
    for file in files_dir.glob("*.md"):
        # Skip special files
        if file.name in config.special_files:
            continue

        links = find_file_links(file, state_dirs)

        if not links:
            errors.append(
                f"Missing link: {file.name} not linked in any state directory"
            )
        elif len(links) > 1:
            states = [link.parent.name for link in links]
            errors.append(
                f"Multiple links: {file.name} linked in multiple states: {', '.join(states)}"
            )

    # Check for broken symlinks in state directories
    for state_dir in state_dirs:
        for link in state_dir.glob("*.md"):
            if not link.is_symlink():
                errors.append(f"Not a symlink: {link.relative_to(repo_root)}")
                continue

            try:
                target = link.resolve()
                if not target.exists():
                    errors.append(
                        f"Broken link: {link.relative_to(repo_root)} -> {target}"
                    )
                elif not str(target).startswith(str(files_dir)):
                    errors.append(
                        f"Invalid link: {link.relative_to(repo_root)} points outside {config.type_name}/all/"
                    )
            except Exception as e:
                errors.append(f"Error resolving {link.relative_to(repo_root)}: {e}")

    return errors


def main(argv: Sequence[str] = sys.argv) -> int:
    """Main function."""
    parser = argparse.ArgumentParser(
        description="Verify file symlinks in state-based directories"
    )
    parser.add_argument(
        "--type",
        choices=list(CONFIGS.keys()),
        default="tasks",
        help="Type of files to check (default: tasks)",
    )
    args = parser.parse_args(argv[1:])

    errors = verify_links(type_name=args.type)

    if errors:
        print("\n".join(errors))
        return 1
    return 0


def test_verify_links():
    """Test the link verification for both tasks and tweets."""

    with tempfile.TemporaryDirectory() as tmpdir:
        root = Path(tmpdir)

        # Test tasks
        def test_tasks():
            # Create test directory structure
            tasks_dir = root / "tasks"
            for d in ["all", "new", "active", "paused", "done", "cancelled"]:
                (tasks_dir / d).mkdir(parents=True)

            # Create test files
            (tasks_dir / "all/task1.md").write_text("task1")
            (tasks_dir / "all/task2.md").write_text("task2")
            (tasks_dir / "all/no-active-task.md").write_text("no active task")

            # Create valid symlinks
            (tasks_dir / "active/task1.md").symlink_to("../all/task1.md")
            (tasks_dir / "done/task2.md").symlink_to("../all/task2.md")
            (root / "CURRENT_TASK.md").symlink_to("tasks/all/task1.md")

            # Test valid configuration
            errors = verify_links(root, "tasks")
            assert len(errors) == 0

            # Test missing link
            (tasks_dir / "all/task3.md").write_text("task3")
            errors = verify_links(root, "tasks")
            assert len(errors) == 1
            assert "Missing link: task3.md" in errors[0]

            # Test multiple links
            (tasks_dir / "new/task1.md").symlink_to("../all/task1.md")
            errors = verify_links(root, "tasks")
            assert len(errors) == 1
            assert "Multiple links" in errors[0]

            # Test broken link
            (tasks_dir / "active/broken.md").symlink_to("../all/nonexistent.md")
            errors = verify_links(root, "tasks")
            assert len(errors) == 2  # Previous error + new broken link
            assert any("Broken link" in e for e in errors)

        # Test tweets
        def test_tweets():
            # Create test directory structure
            tweets_dir = root / "tweets"
            for d in ["all", "new", "queued", "approved", "posted"]:
                (tweets_dir / d).mkdir(parents=True)

            # Create test files
            (tweets_dir / "all/tweet1.md").write_text("tweet1")
            (tweets_dir / "all/tweet2.md").write_text("tweet2")

            # Create valid symlinks
            (tweets_dir / "queued/tweet1.md").symlink_to("../all/tweet1.md")
            (tweets_dir / "posted/tweet2.md").symlink_to("../all/tweet2.md")

            # Test valid configuration
            errors = verify_links(root, "tweets")
            assert len(errors) == 0

            # Test missing link
            (tweets_dir / "all/tweet3.md").write_text("tweet3")
            errors = verify_links(root, "tweets")
            assert len(errors) == 1
            assert "Missing link: tweet3.md" in errors[0]

            # Test multiple links
            (tweets_dir / "new/tweet1.md").symlink_to("../all/tweet1.md")
            errors = verify_links(root, "tweets")
            assert len(errors) == 1
            assert "Multiple links" in errors[0]

        # Save current directory and change to test directory
        old_cwd = os.getcwd()
        os.chdir(str(root))

        try:
            test_tasks()
            test_tweets()
        finally:
            os.chdir(old_cwd)


if __name__ == "__main__":
    sys.exit(main())
