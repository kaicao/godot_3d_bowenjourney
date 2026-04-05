# Godot engine built game

Openworld 3rd person exploration game.

Created using Ollama + VSCode Copilot Chat


## Lesson learned

### Qwen 3.5
qwen3.5 is good coder, but generate overlly verbose agent skills. But its not using agent skills fluent enough or not mentioned enough in the chat, needs remin in chat.

### Gemma 4
gemma4:31b is good at work with agent skills, but bad coder when work with the game scripts, especially when script file is medium to large size e.g. few hundred lines. And it does not use .vscode/.instructions.md automatically, needs to remid in chat. And it gets really slow some time when generting tokens, might be temp issue with ollama.

### VSCode Copilot Chat Agent
Models tend to find game files and modify even add rule to forbid that must use mcp tools. Need to remind in chat.

VSCode copilot chat Autopilot can get stuck, reason is unknown, need to manual stop it and retry.

