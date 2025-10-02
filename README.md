# Installation
- Clone the repo.
- Create a file called .claude_api_key in the directory where rubber-duck.sh lives.
- Add the script to your /bin/ folder if you'd like!

# Usage
This script acts as a rubber duck debugging assistant that provides
guidance through prose only - no code will be generated.

## Options:
  -d, --detail LEVEL      Detail level (quick|thorough|deep)
  -f, --focus AREA        Focus area (logic|syntax|design|performance|testing)
  -c, --code FILE         Include code file as context
  -o, --output FILE       Save response to file
  -r, --reset             Reset conversation history
  -s, --show-history      Show current conversation history
  -h, --help              Show this help message

## Examples:
./rubber-duck.sh "My recursive function isn't returning the right values"
./rubber-duck.sh -f logic -d thorough "Having trouble with my sorting algorithm"
./rubber-duck.sh -c mycode.c "Why isn't my hashmap function working?"
./rubber-duck.sh -c algorithm.py -f performance "This seems slow, what should I consider?"
