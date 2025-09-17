#!/bin/bash

# Rubber Duck Debugging Assistant Script
# This script configures Claude to act as a debugging assistant that provides
# only prose guidance without generating any code

# Get the directory where the actual script is located
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# Configuration
CLAUDE_API_URL="https://api.anthropic.com/v1/messages"
API_KEY_FILE="$SCRIPT_DIR/.claude_api_key"
HISTORY_FILE="$SCRIPT_DIR/.claude_debug_history"
MODEL="claude-opus-4-1-20250805"

# Color codes for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 [OPTIONS] \"Your debugging question or code issue\""
    echo ""
    echo "This script acts as a rubber duck debugging assistant that provides"
    echo "guidance through prose only - no code will be generated."
    echo ""
    echo "Options:"
    echo "  -d, --detail LEVEL      Detail level (quick|thorough|deep)"
    echo "  -f, --focus AREA        Focus area (logic|syntax|design|performance|testing)"
    echo "  -c, --code FILE         Include code file as context"
    echo "  -o, --output FILE       Save response to file"
    echo "  -r, --reset             Reset conversation history"
    echo "  -s, --show-history      Show current conversation history"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 \"My recursive function isn't returning the right values\""
    echo "  $0 -f logic -d thorough \"Having trouble with my sorting algorithm\""
    echo "  $0 -c mycode.c \"Why isn't my hashmap function working?\""
    echo "  $0 -c algorithm.py -f performance \"This seems slow, what should I consider?\""
}

# Default values
DETAIL_LEVEL="thorough"
FOCUS_AREA=""
CODE_FILE=""
OUTPUT_FILE=""
RESET_HISTORY=false
SHOW_HISTORY=false
PROMPT=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--detail)
            DETAIL_LEVEL="$2"
            shift 2
            ;;
        -f|--focus)
            FOCUS_AREA="$2"
            shift 2
            ;;
        -c|--code)
            CODE_FILE="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -r|--reset)
            RESET_HISTORY=true
            shift
            ;;
        -s|--show-history)
            SHOW_HISTORY=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option $1"
            usage
            exit 1
            ;;
        *)
            PROMPT="$1"
            shift
            ;;
    esac
done

# Check if prompt is provided (unless showing history or resetting)
if [[ -z "$PROMPT" && "$SHOW_HISTORY" != true && "$RESET_HISTORY" != true ]]; then
    echo -e "${RED}Error: Please describe your debugging issue${NC}"
    usage
    exit 1
fi

# Check if API key file exists
if [[ ! -f "$API_KEY_FILE" ]]; then
    echo -e "${RED}Error: API key file not found at $API_KEY_FILE${NC}"
    echo "Please create the file and add your Claude API key."
    exit 1
fi

# Read API key
API_KEY=$(cat "$API_KEY_FILE")

# Check if code file exists
if [[ -n "$CODE_FILE" && ! -f "$CODE_FILE" ]]; then
    echo -e "${RED}Error: Code file '$CODE_FILE' not found${NC}"
    exit 1
fi
if [[ "$RESET_HISTORY" == true ]]; then
    rm -f "$HISTORY_FILE"
    echo -e "${GREEN}Conversation history reset${NC}"
    exit 0
fi

# Handle show history
if [[ "$SHOW_HISTORY" == true ]]; then
    if [[ -f "$HISTORY_FILE" ]]; then
        echo -e "${BLUE}Current conversation history:${NC}"
        echo "----------------------------------------"
        cat "$HISTORY_FILE"
    else
        echo -e "${YELLOW}No conversation history found${NC}"
    fi
    exit 0
fi

# Properly escape JSON strings
escape_json() {
    local input="$1"
    # Escape backslashes first, then quotes, then newlines and other control chars
    echo "$input" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g' | sed 's/\t/\\t/g' | sed 's/\r/\\r/g'
}

# Build conversation messages array including history
build_messages() {
    local system_prompt="You are a rubber duck debugging assistant for a student who needs to write all their code themselves for school. Your role is to help them think through problems by asking clarifying questions and providing guidance through prose only.

    CRITICAL RULES:
    - NEVER generate, write, or provide any code snippets, functions, or code examples
    - NEVER show syntax or code structure, even as examples
    - Only provide conceptual guidance, debugging strategies, and thought-provoking questions
    - Help them break down problems into logical steps
    - Guide them to discover solutions themselves through questioning
    - Focus on problem-solving methodology and debugging approaches
    - Respond only in prose paragraphs - no bullet points, code blocks, or structured lists

    Your response should help them think through their problem systematically."

    local detail_instruction=""
    case "$DETAIL_LEVEL" in
        quick)
            detail_instruction=" Provide a concise response that gets straight to the key debugging questions and approaches."
            ;;
        thorough)
            detail_instruction=" Provide a comprehensive response that explores multiple angles and debugging strategies."
            ;;
        deep)
            detail_instruction=" Provide an in-depth analysis that covers advanced debugging concepts and edge cases to consider."
            ;;
    esac

    local focus_instruction=""
    case "$FOCUS_AREA" in
        logic)
            focus_instruction=" Focus particularly on logical flow, algorithm correctness, and reasoning through the problem step by step."
            ;;
        syntax)
            focus_instruction=" Focus on helping them think through language-specific issues and common syntax pitfalls, but without showing code."
            ;;
        design)
            focus_instruction=" Focus on architectural decisions, design patterns, and overall code structure considerations."
            ;;
        performance)
            focus_instruction=" Focus on performance considerations, optimization strategies, and efficiency concerns."
            ;;
        testing)
            focus_instruction=" Focus on testing approaches, edge cases to consider, and validation strategies."
            ;;
    esac

    system_prompt+="$detail_instruction$focus_instruction"
    
    # Create a temporary file to build the JSON
    local temp_json=$(mktemp)
    
    # Start JSON array
    echo '[' > "$temp_json"
    
    # Add system message
    echo '  {' >> "$temp_json"
    echo '    "role": "user",' >> "$temp_json"
    echo "    \"content\": \"$(escape_json "$system_prompt")\"" >> "$temp_json"
    echo '  },' >> "$temp_json"
    
    # Add conversation history if it exists
    if [[ -f "$HISTORY_FILE" ]]; then
        while IFS= read -r line; do
            if [[ "$line" == "USER:"* ]]; then
                user_content=$(echo "$line" | sed 's/^USER: //')
                echo '  {' >> "$temp_json"
                echo '    "role": "user",' >> "$temp_json"
                echo "    \"content\": \"$(escape_json "$user_content")\"" >> "$temp_json"
                echo '  },' >> "$temp_json"
            elif [[ "$line" == "ASSISTANT:"* ]]; then
                assistant_content=$(echo "$line" | sed 's/^ASSISTANT: //')
                echo '  {' >> "$temp_json"
                echo '    "role": "assistant",' >> "$temp_json"
                echo "    \"content\": \"$(escape_json "$assistant_content")\"" >> "$temp_json"
                echo '  },' >> "$temp_json"
            fi
        done < "$HISTORY_FILE"
    fi
    
    # Add current user message with code context if provided
    local user_message="$PROMPT"

    if [[ -n "$CODE_FILE" ]]; then
        local code_filename
        code_filename=$(basename "$CODE_FILE")
        local code_content
        code_content=$(cat "$CODE_FILE")
        user_message+="

    Here's my code for context:

    \`\`\`$code_filename
    $code_content
    \`\`\`"
    fi

    # Now safely escape the entire constructed message
    local escaped_user_message
    escaped_user_message=$(escape_json "$user_message")

    echo '  {' >> "$temp_json"
    echo '    "role": "user",' >> "$temp_json"
    echo "    \"content\": \"$escaped_user_message\"" >> "$temp_json"
    echo '  }' >> "$temp_json"
        
    # Close JSON array
    echo ']' >> "$temp_json"
    
    cat "$temp_json"
    rm "$temp_json"
}

# Make API call to Claude
call_claude() {
    local messages=$(build_messages)
    
    echo -e "${BLUE}Consulting your rubber duck debugging assistant...${NC}"
    
    local response=$(curl -s -X POST "$CLAUDE_API_URL" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        --data-binary @<(echo "{\"model\": \"$MODEL\", \"max_tokens\": 4000, \"messages\": $(cat <(echo "$messages"))}"))
    
    # Check for API errors
    if echo "$response" | jq -e '.error' > /dev/null 2>&1; then
        echo -e "${RED}API Error:${NC}"
        echo "$response" | jq -r '.error.message'
        exit 1
    fi
    
    # Extract the content from the response
    local content=$(echo "$response" | jq -r '.content[0].text // empty')
    
    if [[ -z "$content" ]]; then
        echo -e "${RED}Error: No content received from Claude${NC}"
        echo "Raw response: $response"
        exit 1
    fi
    
    echo -e "${GREEN}🦆 Debugging Guidance:${NC}"
    echo "----------------------------------------"
    echo "$content"
    
    # Save conversation to history
    if [[ -n "$CODE_FILE" ]]; then
        echo "USER: $PROMPT (with code file: $CODE_FILE)" >> "$HISTORY_FILE"
    else
        echo "USER: $PROMPT" >> "$HISTORY_FILE"
    fi
    echo "ASSISTANT: $content" >> "$HISTORY_FILE"
    
    # Save to file if specified
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$content" > "$OUTPUT_FILE"
        echo -e "${YELLOW}Guidance saved to: $OUTPUT_FILE${NC}"
    fi
}

# Main execution
main() {
    echo -e "${BLUE}🦆 Rubber Duck Debugging Assistant${NC}"
    echo "Issue: $PROMPT"
    if [[ -n "$CODE_FILE" ]]; then
        echo "Code File: $CODE_FILE"
    fi
    echo "Detail Level: $DETAIL_LEVEL"
    
    if [[ -n "$FOCUS_AREA" ]]; then 
        echo "Focus Area: $FOCUS_AREA"
    fi
    
    echo "----------------------------------------"
    
    call_claude
}

# Check dependencies
check_dependencies() {
    if ! command -v curl &> /dev/null; then
        echo -e "${RED}Error: curl is required but not installed${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}Error: jq is required but not installed${NC}"
        echo "Install with: sudo apt-get install jq  # or brew install jq"
        exit 1
    fi
}

# Run dependency check and main function
check_dependencies
main
