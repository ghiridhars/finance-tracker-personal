import json
from collections import defaultdict

with open('graphify-out/graph.json') as f:
    graph = json.load(f)

nodes = graph.get('nodes', [])
edges = graph.get('links', [])

# Track incoming and outgoing edges for each node id
incoming = defaultdict(int)
outgoing = defaultdict(int)
for edge in edges:
    incoming[edge['target']] += 1
    outgoing[edge['source']] += 1

dead_functions = []
for node in nodes:
    # Only look at backend service functions
    if 'backend/app/services' in node.get('file', '') and node.get('type') == 'function':
        # If it has 0 incoming edges and doesn't start with __
        if incoming[node['id']] == 0 and not node['name'].startswith('__'):
            dead_functions.append((node['name'], node['file']))

print(f"Total dead functions found: {len(dead_functions)}")
for func, file in dead_functions:
    print(f" - {func} in {file}")
