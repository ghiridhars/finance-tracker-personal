import json

with open('graphify-out/graph.json') as f:
    graph = json.load(f)

screens = []
for node in graph.get('nodes', []):
    if 'frontend/lib/screens' in node.get('file', '') and node.get('type') == 'class' and node['name'].endswith('Screen'):
        screens.append(node['name'])

print("Found Screens:", sorted(list(set(screens))))
