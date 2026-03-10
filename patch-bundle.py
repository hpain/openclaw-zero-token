with open('dist/reply-BUaW1r6O.mjs', 'r', encoding='utf-8') as f:
    content = f.read()

# Find and remove the dead monkeypatch block that references SYNC_PLUGIN_SDK
# We want to remove everything between (and including) 'if (!globalThis.__OPENCLAW_PLUGIN_SDK__)...' and its closing '}'
# followed by the empty lines before 'return jitiLoader;'
old_block = (
    '\t\tif (!globalThis.__OPENCLAW_PLUGIN_SDK__) {\n'
    '\t\t\tconsole.log("[DEBUG-LDR] initializing memory-only jiti plugin-sdk cache bypass via SYNCHRONOUS ESM import");\n'
)

idx = content.find(old_block)
if idx == -1:
    print('Block not found!')
else:
    # Find end of this if block - look for '\t\t}\n\t\t\n\t\treturn jitiLoader;'
    end_marker = '\t\t}\n\t\t\n\t\treturn jitiLoader;'
    end_idx = content.find(end_marker, idx)
    if end_idx == -1:
        print('End marker not found!')
    else:
        # Remove the if block up to (but not including) 'return jitiLoader;'
        end_of_block = end_idx + len('\t\t}\n\t\t\n')
        removed = content[idx:end_of_block]
        print('Removing block of length:', len(removed))
        # Replace with just the extra blank line
        content = content[:idx] + '\t\t\n' + content[end_of_block:]
        with open('dist/reply-BUaW1r6O.mjs', 'w', encoding='utf-8') as f:
            f.write(content)
        print('Done!')
