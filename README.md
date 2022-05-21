# metaportal

Portals and pockets in metauni

## Generating a Release

To generate a release, run
```bash
rojo build --output metaportal.rbxmx release.project.json
```

This packages the `src/common`, `src/client` and `src/gui` code inside the server folder (`src/server`) called `metaportal`. 

`src/server/Startup.server.lua` will redistribute this code into the appropriate client folders when the game starts.
