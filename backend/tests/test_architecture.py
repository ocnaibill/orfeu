"""Garante a fronteira: só app/sources fala com Tidal, YT Music e Soulseek."""
import ast
import pathlib

APP = pathlib.Path(__file__).resolve().parent.parent / "app"
PROVIDER_MODULES = {
    "app.services.tidal_provider",
    "app.services.catalog_provider",
    "app.services.slskd_client",
}
# Módulos de provider que podem se importar entre si (detalhe interno de cada provider).
PROVIDER_FILES = {"tidal_provider.py", "catalog_provider.py", "slskd_client.py"}


def _imports(path):
    tree = ast.parse(path.read_text())
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            yield node.module
        elif isinstance(node, ast.Import):
            for alias in node.names:
                yield alias.name


def test_only_sources_package_imports_the_providers():
    offenders = []
    for path in APP.rglob("*.py"):
        rel = path.relative_to(APP)
        if rel.parts[0] == "sources" or path.name in PROVIDER_FILES:
            continue
        bad = PROVIDER_MODULES.intersection(_imports(path))
        if bad:
            offenders.append(f"{rel}: {sorted(bad)}")
    assert not offenders, "Use app.sources.registry.get_sources() em vez de importar o provider:\n" + "\n".join(offenders)
