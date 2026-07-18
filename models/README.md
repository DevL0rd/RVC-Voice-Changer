# Voice models

Give every voice its own directory. The daemon discovers one `.pth` model and
an optional `.index` retrieval index in each immediate subdirectory:

```text
models/
└── Example Voice/
    ├── ExampleVoice.pth
    └── added_IVF.index
```

Model and index files are intentionally ignored by Git.
