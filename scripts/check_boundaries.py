"""
模块边界检查脚本。

检查以下规则：
1. 不允许跨模块直接导入 DAO（只能通过 Service 调用）
2. Service 层不允许直接使用 db.query() / session.query() / session.execute()
3. Router 层不允许直接导入 DAO
4. Router 层不允许直接使用 db.query()

用法：python scripts/check_boundaries.py
退出码：0 = 无违规，1 = 发现违规
"""
import ast
import sys
from pathlib import Path


def discover_modules(app_dir: Path) -> list[str]:
    """自动发现 app/ 下的所有业务模块"""
    modules = []
    for child in app_dir.iterdir():
        if (
            child.is_dir()
            and child.name != "common"
            and child.name != "__pycache__"
            and not child.name.startswith(".")
            and (child / "__init__.py").exists()
        ):
            modules.append(child.name)
    return sorted(modules)


def get_imports(tree: ast.AST) -> list[tuple[int, str]]:
    """提取文件中所有 import 语句的行号和模块路径"""
    imports = []
    for node in ast.walk(tree):
        if isinstance(node, ast.ImportFrom) and node.module:
            imports.append((node.lineno, node.module))
        elif isinstance(node, ast.Import):
            for alias in node.names:
                imports.append((node.lineno, alias.name))
    return imports


def check_cross_module_dao_import(
    filepath: Path, tree: ast.AST, current_module: str, all_modules: list[str]
) -> list[str]:
    """检查是否跨模块直接导入了 DAO"""
    errors = []
    for lineno, module_path in get_imports(tree):
        for other_module in all_modules:
            if other_module == current_module:
                continue
            if f"app.{other_module}.dao" in module_path:
                errors.append(
                    f"  {filepath}:{lineno}: "
                    f"不要直接导入 {other_module} 模块的 DAO，"
                    f"请通过 {other_module} 模块的 Service 调用"
                )
    return errors


def check_direct_db_access(filepath: Path, source: str, layer: str) -> list[str]:
    """检查是否在 service/router 层直接使用了数据库查询"""
    errors = []
    forbidden = [
        "db.query(",
        "session.query(",
        "db.execute(",
        "session.execute(",
        ".query(select(",
    ]
    for i, line in enumerate(source.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        for pattern in forbidden:
            if pattern in line:
                errors.append(
                    f"  {filepath}:{i}: "
                    f"{layer} 层不要直接查询数据库，请通过 DAO 层操作"
                )
                break
    return errors


def check_router_dao_import(
    filepath: Path, tree: ast.AST, all_modules: list[str]
) -> list[str]:
    """检查 router 层是否直接导入了 DAO"""
    errors = []
    for lineno, module_path in get_imports(tree):
        for module in all_modules:
            if f"app.{module}.dao" in module_path:
                errors.append(
                    f"  {filepath}:{lineno}: "
                    f"Router 层不要直接导入 DAO，请通过 Service 调用"
                )
    return errors


def check_file(filepath: Path, current_module: str, all_modules: list[str]) -> list[str]:
    """检查单个文件"""
    errors = []
    try:
        source = filepath.read_text(encoding="utf-8")
        tree = ast.parse(source)
    except (SyntaxError, UnicodeDecodeError):
        return []

    filename = filepath.name

    # 跨模块 DAO 导入检查
    errors.extend(
        check_cross_module_dao_import(filepath, tree, current_module, all_modules)
    )

    # Service 层检查
    if filename == "service.py" or filename.endswith("_service.py"):
        errors.extend(check_direct_db_access(filepath, source, "Service"))

    # Router 层检查
    if filename == "router.py" or filename.endswith("_router.py"):
        errors.extend(check_direct_db_access(filepath, source, "Router"))
        errors.extend(check_router_dao_import(filepath, tree, all_modules))

    return errors


def main() -> int:
    app_dir = Path("app")
    if not app_dir.exists():
        print("错误：找不到 app/ 目录，请在项目根目录运行此脚本")
        return 1

    modules = discover_modules(app_dir)
    if not modules:
        print("未发现任何业务模块（app/ 下除 common 外的目录）")
        return 0

    print(f"发现 {len(modules)} 个模块: {', '.join(modules)}")
    print("检查模块边界...\n")

    all_errors = []
    for module in modules:
        module_dir = app_dir / module
        for py_file in module_dir.rglob("*.py"):
            if "tests" in py_file.parts or "test_" in py_file.name:
                continue
            errors = check_file(py_file, module, modules)
            all_errors.extend(errors)

    if all_errors:
        print(f"发现 {len(all_errors)} 个边界违规:\n")
        for error in all_errors:
            print(error)
        print(f"\n共 {len(all_errors)} 个违规需要修复。")
        return 1
    else:
        print("所有模块边界检查通过。")
        return 0


if __name__ == "__main__":
    sys.exit(main())
