# Compare this agent harness to another, useful when checking for updates/changes to upstream
# Usage: ./compare.sh <path_to_other_agent>
#
echo "Comparing this agent to another..."

set -e

# Get the path to the other agent
if [ -z "$1" ]; then
  echo "Usage: ./compare.sh <path_to_other_agent>"
  exit 1
fi

AGENT_PATH=$1

# Compare the two agents
# Including files in the agent harness:
#  - ARCHITECTURE.md
#  - scripts/
#
# Excluding information about the agent itself, like:
#  - README.md
#  - ABOUT.md
#  - journal/
#  - knowledge/
#  - people/
#  - tweets/
#  - email/

function run_codeblock() {
    # usage: run_codeblock diff "file1" "file2"
    # outputs the result of a command as a ```<command> codeblock
    echo "Running command: $@"
    echo "\`\`\`$@"
    eval "$@" || true
    echo "\`\`\`"
}

function diff_codeblock() {
    run_codeblock diff -r "$1" "$AGENT_PATH/$2"
}

# Store diffs in a variable
diffs=""
diffs+=$(diff_codeblock "ARCHITECTURE.md")
diffs+=$(diff_codeblock "scripts/")
diffs+=$(diff_codeblock ".pre-commit-config.yaml")
if [ -z "$diffs" ]; then
  echo "No differences found, exiting..."
  exit 0
fi

echo "Differences found:"
printf "%s\n" "$diffs"

# Ask if the user wants to sync the changes using a gptme agent
echo
read -p "Would you like to sync these changes to the gptme agent? (y/n) " -r response

if [ "$response" != "y" ]; then
  echo "Exiting..."
  exit 0
fi

printf "%s\n" "$diffs" | gptme "We want to sync the changes in our agent with the upstream agent-template, either repo may have the best and latest changes, so you need to determine which to choose. Here are the changes we found"

# Exit with the status of the last command
exit $?
