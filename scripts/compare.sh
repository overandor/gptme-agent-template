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
    echo
    echo "\`\`\`$@"
    eval "$@" || true
    echo "\`\`\`"
    echo
}

function diff_codeblock() {
    run_codeblock diff -u -r "$1" "$AGENT_PATH/$1"
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

printf "%s\n" "$diffs" | gptme "We need to synchronize changes between two repositories:
1. The template repository (source of core functionality and best practices)
2. The agent instance (which may have improvements that should be upstreamed)

For each difference found, please:
- Analyze whether the change belongs in the template, the instance, or both
- Consider:
  - Is it a generic improvement that benefits all agents? (→ template)
  - Is it instance-specific customization? (→ instance)
  - Is it a bug fix or enhancement that works for both? (→ both)
  - Does it maintain separation between template and instance concerns?

Here are the differences found. Please analyze each and suggest appropriate synchronization:"

# Exit with the status of the last command
exit $?
