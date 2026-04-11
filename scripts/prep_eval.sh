#!/bin/bash
# prep_eval.sh: Merge SKILL.md with test instructions for Promptfoo

ROOT_DIR=$(dirname "$(dirname "$(realpath "$0")")")
TEST_DIR="$ROOT_DIR/tests"

# Combine SKILL.md and test instructions
{
  cat "$ROOT_DIR/SKILL.md"
  echo -e "\n\n--- EVALUATION INSTRUCTIONS ---\n"
  echo "You are an AI assistant acting as the Doppler Manager. Follow the instructions in the SKILL definition above to answer the user's query."
  echo "User Query: {{ question }}"
} > "$TEST_DIR/final_eval_prompt.txt"

echo "Merged evaluation prompt created at $TEST_DIR/final_eval_prompt.txt"
