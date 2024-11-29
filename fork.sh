#!/bin/bash
set -euo pipefail

# Check arguments
if [ "$#" -ne 1 ] && [ "$#" -ne 2 ]; then
    echo "Usage: $0 <new_agent_workspace> [<new_agent_name>]"
    echo "Example: $0 alice-agent Alice"
    exit 1
fi

# Get the directory containing this script
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$1"

# If target is not an absolute path and doesn't start with ./ or ../
if [[ "$TARGET_DIR" != /* ]] && [[ "$TARGET_DIR" != ./* ]] && [[ "$TARGET_DIR" != ../* ]]; then
    TARGET_DIR="$(realpath ".")/${TARGET_DIR}"
fi

# Create parent directories if needed
mkdir -p "$(dirname "$TARGET_DIR")"

# If a name is provided, use it
# Else, extract agent name from the last directory component, whether it has -agent suffix or not
NEW_AGENT="${2:-$(basename "$TARGET_DIR" | sed 's/-agent$//')}"
# Name of agent in template, to be replaced
NAME_TEMPLATE="gptme-agent"

# Check if directory exists
if [ -d "$TARGET_DIR" ]; then
    # Check if directory is empty
    if [ -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]; then
        echo "Error: Target directory exists and is not empty: $TARGET_DIR"
        exit 1
    fi
    echo "Warning: Target directory exists but is empty, continuing..."
fi

echo -e "\nCreating new agent '$NEW_AGENT' in directory '$TARGET_DIR'..."

# Create core directory structure
echo "Creating directory structure..."
mkdir -p "${TARGET_DIR}"/{journal,tasks/{all,active,done,new,paused,cancelled,templates},projects,knowledge,people/templates,scripts/precommit}

# Copy core files and directories
echo "Copying core files..."

function copy_file() {
    # copies file/directory
    cp -r "${SOURCE_DIR}/$1" "${TARGET_DIR}/"
    # replaces NAME_TEMPLATE with NEW_AGENT in file contents
    find "${TARGET_DIR}/$1" -type f -exec sed -i '' "s/${NAME_TEMPLATE}/${NEW_AGENT}/g" {} \;
    # runs chmod +x on scripts
    find "${TARGET_DIR}/$1" -type f -name "*.sh" -exec chmod +x {} \;
}

# Core documentation and configuration
copy_file Makefile
copy_file ARCHITECTURE.md
copy_file .pre-commit-config.yaml
copy_file scripts
copy_file run.sh
# replace gptme-agent with the new agent name
cat "${SOURCE_DIR}/fork.sh" | sed "s/gptme-agent/${NEW_AGENT}/g" > "${TARGET_DIR}/fork.sh"
chmod +x "${TARGET_DIR}/fork.sh"

# Copy base knowledge
cp "${SOURCE_DIR}/knowledge/agent-forking.md" "${TARGET_DIR}/knowledge/"
cp "${SOURCE_DIR}/knowledge/forking-workspace.md" "${TARGET_DIR}/knowledge/"

# Copy person template
cp "${SOURCE_DIR}/people/templates/"* "${TARGET_DIR}/people/templates/" 2>/dev/null || true
cat "${SOURCE_DIR}/people/templates/person.md" | sed "s/${NAME_TEMPLATE}/${NEW_AGENT}/g" > "${TARGET_DIR}/people/templates/person.md"

# Initialize tasks
echo "# No Active Task" > "${TARGET_DIR}/tasks/all/no-active-task.md"

# Initial setup task from template
cp "${SOURCE_DIR}/tasks/templates/initial-agent-setup.md" "${TARGET_DIR}/tasks/templates/"
cp "${SOURCE_DIR}/tasks/templates/initial-agent-setup.md" "${TARGET_DIR}/tasks/all/"
ln -sf "../all/initial-agent-setup.md" "${TARGET_DIR}/tasks/active/"
ln -sf "./tasks/all/initial-agent-setup.md" "${TARGET_DIR}/CURRENT_TASK.md"

# Create projects README
cat > "${TARGET_DIR}/projects/README.md" << EOL
# Projects

This directory contains symlinks to the projects ${NEW_AGENT} works with.
EOL

# Create basic ABOUT.md template
cat > "${TARGET_DIR}/ABOUT.md" << EOL
# About ${NEW_AGENT}

## Background
[Brief background about ${NEW_AGENT}]

## Personality
[${NEW_AGENT}'s personality traits]

## Tools
[Available tools and capabilities]

## Goals
[${NEW_AGENT}'s primary goals and objectives]

## Values
[Core values and principles]
EOL

# Create README
# Replace occurrences of NAME_TEMPLATE with NEW_AGENT
# Strip any <!--template--><!--/template--> comments
cat "${SOURCE_DIR}/README.md" |
    sed "s/${NAME_TEMPLATE}-template/${NEW_AGENT}/g" |
    sed "s/${NAME_TEMPLATE}/${NEW_AGENT}/g" |
    sed '/<!--template-->/, /<!--\/template-->/d' > "${TARGET_DIR}/README.md"

# Create initial TASKS.md with setup as first task
cat > "${TARGET_DIR}/TASKS.md" << EOL
# Tasks

Active tasks and their current status.

## Current Task
- 🏃 [Initial Agent Setup](./tasks/all/initial-agent-setup.md)

## System Development
- 🏃 Complete initial setup
  - [ ] Establish identity and purpose
  - [ ] Begin first task
EOL

# Create initial gptme.toml
cat > "${TARGET_DIR}/gptme.toml" << EOL
files = [
  "README.md",
  "ARCHITECTURE.md",
  "ABOUT.md",
  "TASKS.md",
  "CURRENT_TASK.md",
  "projects/README.md",
  "gptme.toml"
]
EOL

# Create creator profile
cat > "${TARGET_DIR}/people/creator.md" << EOL
# Creator

## Basic Information
- Name: [Creator's name]
- Relationship to ${NEW_AGENT}: Creator
- First interaction: Creation
- Last interaction: Ongoing

## Contact Information
[Creator's preferred contact methods]

## Notes & History
- Created ${NEW_AGENT} using the gptme agent architecture
EOL

# Initialize git
(cd "${TARGET_DIR}" && git init && git add . && git commit -m "feat: initialize ${NEW_AGENT} agent workspace")

# Run checks
echo
echo "Running pre-commit checks..."
(cd "${TARGET_DIR}" && pre-commit run --all-files)

(cd "${TARGET_DIR}" && ./run.sh --dry-run)

TARGET_DIR_RELATIVE="./$(realpath --relative-to="$(pwd)" "${TARGET_DIR}")"

echo "
Agent workspace created successfully! Next steps:
1. cd ${TARGET_DIR_RELATIVE}
2. Start the agent with: ./run.sh
3. The agent will guide you through the setup interview
4. Follow the agent's instructions to establish its identity

The new agent workspace is ready in: ${TARGET_DIR}"
