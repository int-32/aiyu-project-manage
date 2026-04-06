---
name: init-project
description: >
  初始化一个新的 Python FastAPI 项目，搭建完整的基础设施。
  包括分层架构、公共基类、数据流模式、工具链配置、边界检查、
  端到端流程测试框架、CLAUDE.md 模板。
  当用户说"初始化项目"、"创建新项目"、"搭建项目骨架"时使用。
disable-model-invocation: true
---

# 项目初始化 Skill

按以下步骤初始化项目。每一步完成后告诉用户进度。

## 第一步：收集信息

用 AskUserQuestion 逐步询问：
1. 项目名称（英文，用于包名和目录名）
2. 项目简要描述（一句话）
3. 需要哪些业务模块（如：user, order, product，至少一个）
4. 数据库类型（PostgreSQL / MySQL / SQLite）
5. 是否需要用户认证模块
6. 对于每个模块，询问：
   - 核心实体是否有状态流转（如订单有 pending→paid→shipped）
   - 如果有，具体的状态和合法转换路径是什么
   - 每个状态转换会触发哪些跨模块的副作用（如扣库存、发通知）
   - 是否需要软删除

## 第二步：创建项目结构

```
{project_name}/
├── app/
│   ├── __init__.py
│   ├── main.py                    # FastAPI 入口，注册路由，配置异常处理器
│   ├── config.py                  # pydantic-settings 配置管理
│   ├── database.py                # 数据库连接和 Session 管理
│   ├── common/                    # 公共基础设施
│   │   ├── __init__.py
│   │   ├── base_model.py          # Base, SoftDeleteMixin
│   │   ├── base_dao.py            # BaseDAO（自动软删除过滤）
│   │   ├── base_service.py        # BaseService
│   │   └── exceptions.py          # 公共异常类
│   └── {module}/                  # 业务模块（每个模块重复此结构）
│       ├── __init__.py            # 职责声明（负责/不负责/对外暴露）
│       ├── model.py               # ORM 模型 + relationship + 状态流转 + 副作用定义
│       ├── dao.py                 # 数据访问层，继承 BaseDAO
│       ├── service.py             # 业务逻辑，副作用 handler
│       ├── router.py              # API 路由
│       ├── schemas.py             # Pydantic 请求/响应模型
│       ├── CLAUDE.md              # 模块专属规则和容易犯的错误
│       └── tests/
│           ├── __init__.py
│           ├── test_dao.py        # 数据访问层测试
│           ├── test_service.py    # 业务逻辑测试
│           └── test_data_flow.py  # 模块内数据流测试（状态转换+副作用）
├── tests/
│   ├── __init__.py
│   ├── conftest.py                # 全局 fixtures（测试数据库、Session）
│   ├── factories.py               # 测试数据工厂
│   └── flows/                     # 端到端业务流程测试
│       ├── __init__.py
│       └── test_{module}_flow.py  # 每个核心流程一个文件
├── scripts/
│   ├── check_boundaries.py        # 模块边界检查
│   └── pre-commit                 # git pre-commit hook（安装到 .git/hooks/）
├── docs/
│   └── migration/                 # 迁移文档（旧项目迁移时使用）
├── .claude/
│   ├── settings.json              # Claude Code hook（提交前提醒）
│   └── skills/
│       ├── add-module/
│       │   └── SKILL.md
│       └── entropy-review/
│           └── SKILL.md
├── CLAUDE.md
├── ruff.toml
├── pyrightconfig.json
├── pytest.ini
├── requirements.txt
└── README.md
```

## 第三步：创建公共基础设施

### app/common/base_model.py

```python
"""
公共模型基类。

所有业务模型必须继承 Base。
需要软删除机制的模型额外继承 SoftDeleteMixin。
"""
from datetime import datetime, timezone
from sqlalchemy import Column, Integer, DateTime, Boolean
from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """所有模型的基类，提供 id 和时间戳字段"""
    id = Column(Integer, primary_key=True, autoincrement=True)
    created_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    updated_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False,
    )


class SoftDeleteMixin:
    """
    软删除混入类。

    继承此类的模型使用软删除机制：
    - 删除操作将 is_deleted 设为 True，不物理删除记录
    - BaseDAO._base_query() 会自动过滤 is_deleted=True 的记录
    - 需要查询已删除记录时，使用 BaseDAO._unfiltered_query()
    """
    is_deleted = Column(Boolean, default=False, nullable=False, index=True)
    deleted_at = Column(DateTime(timezone=True), nullable=True)
```

### app/common/base_dao.py

```python
"""
公共数据访问层基类。

所有业务 DAO 必须继承 BaseDAO。
核心机制：_base_query() 自动处理软删除过滤。
所有子类的查询方法都必须基于 _base_query() 构建。
"""
from datetime import datetime, timezone
from typing import TypeVar, Generic, Type
from sqlalchemy.orm import Session
from app.common.base_model import Base, SoftDeleteMixin
from app.common.exceptions import NotFoundError

T = TypeVar("T", bound=Base)


class BaseDAO(Generic[T]):
    """
    数据访问层基类。

    使用方式：
        class OrderDAO(BaseDAO[Order]):
            def __init__(self, db: Session):
                super().__init__(db, Order)

    重要约定：
    - 所有查询方法必须基于 self._base_query() 构建
    - 不要直接使用 self.db.query(self.model)，会绕过软删除过滤
    - 需要包含已删除记录时，使用 self._unfiltered_query()
    """

    def __init__(self, db: Session, model: Type[T]):
        self.db = db
        self.model = model

    def _base_query(self):
        """
        基础查询，自动处理软删除过滤。
        所有子类的查询方法都应该基于此方法构建。
        """
        query = self.db.query(self.model)
        if issubclass(self.model, SoftDeleteMixin):
            query = query.filter(self.model.is_deleted == False)  # noqa: E712
        return query

    def _unfiltered_query(self):
        """不带软删除过滤的查询。仅在明确需要包含已删除记录时使用。"""
        return self.db.query(self.model)

    def get_by_id(self, id: int) -> T | None:
        return self._base_query().filter(self.model.id == id).first()

    def get_by_id_or_raise(self, id: int) -> T:
        record = self.get_by_id(id)
        if record is None:
            raise NotFoundError(f"{self.model.__name__} with id={id} not found")
        return record

    def get_all(self, limit: int = 100, offset: int = 0) -> list[T]:
        return self._base_query().offset(offset).limit(limit).all()

    def create(self, **kwargs) -> T:
        instance = self.model(**kwargs)
        self.db.add(instance)
        self.db.flush()
        return instance

    def update(self, id: int, **kwargs) -> T:
        instance = self.get_by_id_or_raise(id)
        for key, value in kwargs.items():
            setattr(instance, key, value)
        self.db.flush()
        return instance

    def soft_delete(self, id: int) -> T:
        if not issubclass(self.model, SoftDeleteMixin):
            raise TypeError(f"{self.model.__name__} does not support soft delete")
        instance = self.get_by_id_or_raise(id)
        instance.is_deleted = True
        instance.deleted_at = datetime.now(timezone.utc)
        self.db.flush()
        return instance

    def hard_delete(self, id: int) -> None:
        instance = self.get_by_id_or_raise(id)
        self.db.delete(instance)
        self.db.flush()
```

### app/common/base_service.py

```python
"""
公共服务层基类。

Service 层职责：
- 组合 DAO 方法实现业务逻辑
- 处理跨模块调用（通过注入其他模块的 Service）
- 执行状态转换的副作用

Service 层禁止：
- 直接使用 db.query() 或 session.query()
- 直接导入其他模块的 DAO
"""


class BaseService:
    """服务层基类"""
    pass
```

### app/common/exceptions.py

```python
"""项目公共异常类。API 层通过异常处理器将这些异常转换为 HTTP 响应。"""


class AppError(Exception):
    """应用异常基类"""
    def __init__(self, message: str = ""):
        self.message = message
        super().__init__(self.message)


class NotFoundError(AppError):
    """资源不存在"""
    def __init__(self, message: str = "Resource not found"):
        super().__init__(message)


class InvalidStatusTransition(AppError):
    """非法的状态转换"""
    def __init__(self, current: str, target: str, allowed: list[str] | None = None):
        allowed_str = ", ".join(allowed) if allowed else "none"
        message = (
            f"Cannot transition from '{current}' to '{target}'. "
            f"Allowed: [{allowed_str}]"
        )
        super().__init__(message)


class PermissionDeniedError(AppError):
    def __init__(self, message: str = "Permission denied"):
        super().__init__(message)


class BusinessRuleViolation(AppError):
    def __init__(self, message: str = "Business rule violated"):
        super().__init__(message)


class DuplicateError(AppError):
    def __init__(self, message: str = "Resource already exists"):
        super().__init__(message)
```

## 第四步：创建业务模块

对用户指定的每个模块，按以下模板创建。

### {module}/__init__.py

```python
"""
{模块名}模块。

负责：
- （根据用户提供的信息填写）

不负责：
- （根据用户提供的信息填写）

对外暴露：
- {Model}Service: 其他模块通过此 Service 调用本模块能力
"""
```

### {module}/model.py

根据用户提供的信息创建模型：
- 继承 Base（需要软删除则额外继承 SoftDeleteMixin）
- 补全所有 relationship 定义
- 如果实体有状态流转，必须定义以下两个常量：

```python
class Order(Base):
    """
    订单表。

    生命周期：
      （描述完整的状态流转路径）

    关联影响：
      （描述其他实体的变化对本实体的影响）
    """
    __tablename__ = "orders"

    # 状态流转规则
    VALID_TRANSITIONS = {
        "pending":   ["paid", "cancelled"],
        "paid":      ["shipped", "refunded"],
        # ...
    }

    # 状态转换触发的副作用
    # key: (from_status, to_status)
    # value: 需要触发的操作列表，格式为 "模块名.动作"
    TRANSITION_SIDE_EFFECTS = {
        ("pending", "paid"):      ["inventory.deduct", "payment.charge"],
        ("paid", "refunded"):     ["inventory.restore", "payment.refund"],
        # ...
    }

    def can_transition_to(self, new_status: str) -> bool:
        return new_status in self.VALID_TRANSITIONS.get(self.status, [])

    def get_side_effects(self, new_status: str) -> list[str]:
        """获取状态转换时需要触发的副作用"""
        return self.TRANSITION_SIDE_EFFECTS.get(
            (self.status, new_status), []
        )
```

没有状态流转的模型不需要 VALID_TRANSITIONS 和 TRANSITION_SIDE_EFFECTS。

### {module}/dao.py

```python
from sqlalchemy.orm import Session
from app.common.base_dao import BaseDAO
from app.{module}.model import {Model}


class {Model}DAO(BaseDAO[{Model}]):
    def __init__(self, db: Session):
        super().__init__(db, {Model})

    # 模块专属查询方法
    # 所有查询必须基于 self._base_query()
```

### {module}/service.py

如果模型有状态流转和副作用，service 必须包含副作用路由机制：

```python
from app.{module}.dao import {Model}DAO
from app.common.base_service import BaseService
from app.common.exceptions import InvalidStatusTransition


class {Model}Service(BaseService):
    def __init__(
        self,
        {module}_dao: {Model}DAO,
        # 根据 TRANSITION_SIDE_EFFECTS 注入需要的其他模块 Service
    ):
        self.{module}_dao = {module}_dao

        # 副作用路由：Model 中定义的副作用字符串 → 实际处理方法
        self._side_effect_handlers = {
            # "inventory.deduct": self._handle_inventory_deduct,
        }

    def transition_status(self, id: int, new_status: str) -> {Model}:
        """
        状态流转统一入口。

        流程：
        1. 校验转换合法性（Model 层规则）
        2. 执行副作用（调用其他模块 Service）
        3. 副作用全部成功后更新状态（DAO 层）
        """
        instance = self.{module}_dao.get_by_id_or_raise(id)

        if not instance.can_transition_to(new_status):
            raise InvalidStatusTransition(
                current=instance.status,
                target=new_status,
                allowed=instance.VALID_TRANSITIONS.get(instance.status, []),
            )

        for effect in instance.get_side_effects(new_status):
            handler = self._side_effect_handlers.get(effect)
            if handler:
                handler(instance)

        instance.status = new_status
        self.{module}_dao.update(instance.id, status=new_status)
        return instance
```

没有状态流转的模块不需要 transition_status 和副作用路由。

### {module}/CLAUDE.md

模块 CLAUDE.md 只写 __init__.py 中不适合承载的信息。
职责边界已在 __init__.py 的 docstring 中定义，不要在这里重复。

```markdown
# {模块名}模块

职责边界见 __init__.py

## 数据流
（如有状态流转）
- 状态转换规则：model.py → VALID_TRANSITIONS
- 副作用定义：model.py → TRANSITION_SIDE_EFFECTS
- 副作用执行：service.py → _side_effect_handlers

## 容易犯的错误
（初始为空，随使用积累。当 Claude 因不了解某个规则而犯错时，修正后把教训加到这里）
```

### {module}/tests/test_data_flow.py

如果模型有状态流转，必须创建数据流测试：

```python
class TestStatusTransitions:
    """测试所有合法和非法的状态转换"""

    # 为每个合法转换写一个测试
    # 为典型的非法转换写测试（如跳过中间状态）

class TestSideEffects:
    """测试状态转换触发的副作用"""

    # 为每个有副作用的转换写测试，断言副作用是否正确执行

    def test_all_side_effects_have_handlers(self):
        """确保 Model 定义的每个副作用在 Service 中都有 handler"""
        for (from_s, to_s), effects in {Model}.TRANSITION_SIDE_EFFECTS.items():
            for effect in effects:
                assert effect in service._side_effect_handlers, (
                    f"转换 {from_s}→{to_s} 的副作用 '{effect}' 缺少 handler"
                )
```

## 第五步：创建端到端流程测试

对于涉及多模块协作的核心业务流程，在 tests/flows/ 下创建流程测试。

每个流程测试文件覆盖一条完整业务链路：
- 正常路径（happy path）
- 主要的异常路径
- 边界情况（如用户软删除后的影响、库存不足等）

流程测试的编写规范：
- 每个测试方法的注释用中文描述业务含义
- 每个步骤之间用注释标注 "# N. 步骤描述"
- 每个关键步骤后用 assert 验证中间状态
- 不只验证最终结果，也验证过程中的副作用

```python
# tests/flows/test_{业务名}_flow.py
"""
{业务名}完整流程测试。

覆盖从{起点}到{终点}的所有关键路径。
每个测试方法描述一条完整的业务流程。
"""


class Test{Business}HappyPath:
    """正常流程"""

    def test_complete_flow(self, db_session):
        # 1. 前置条件
        ...
        # 2. 第一步操作
        ...
        assert ...  # 验证中间状态
        # 3. 第二步操作
        ...
        assert ...  # 验证副作用
        # N. 最终状态
        assert ...  # 验证最终结果


class Test{Business}Failures:
    """异常路径"""
    ...


class Test{Business}EdgeCases:
    """边界情况"""
    ...
```

## 第六步：创建测试基础设施

### tests/conftest.py

配置测试数据库（SQLite in-memory），提供 db_session fixture。

### tests/factories.py

为每个模块的核心模型提供工厂方法：
- create_{model}()：创建并返回一个实例
- 工厂方法接受关键字参数覆盖默认值
- 提供合理的默认值，减少测试样板代码

```python
def create_user(db: Session, **overrides) -> User:
    defaults = {
        "email": f"test_{uuid4().hex[:8]}@example.com",
        "name": "Test User",
    }
    defaults.update(overrides)
    user = User(**defaults)
    db.add(user)
    db.flush()
    return user
```

## 第七步：创建工具链配置

### ruff.toml

```toml
target-version = "py311"
line-length = 120

[lint]
select = [
  "E",      # 语法错误
  "F",      # pyflakes（未使用的 import/变量）
  "I",      # import 排序
  "N",      # 命名规范
  "UP",     # 现代化写法
  "B",      # bugbear（常见 bug 模式）
  "SIM",    # 可简化的代码
  "T20",    # 禁止 print
  "S",      # 安全检查（SQL注入、硬编码密码）
  "RET",    # return 语句检查
  "ARG",    # 未使用的参数
]

[lint.per-file-ignores]
"tests/**" = ["T20", "S101", "ARG"]
"**/test_*.py" = ["T20", "S101", "ARG"]
"**/conftest.py" = ["ARG"]
```

### pyrightconfig.json

```json
{
  "typeCheckingMode": "basic",
  "pythonVersion": "3.11",
  "reportMissingTypeStubs": false,
  "reportUnknownMemberType": false,
  "exclude": ["**/__pycache__", ".venv"]
}
```

### pytest.ini

```ini
[pytest]
testpaths = tests app
asyncio_mode = auto
addopts = -v --tb=short
python_files = test_*.py
python_classes = Test*
python_functions = test_*
```

### requirements.txt

```
fastapi>=0.100.0
uvicorn[standard]>=0.23.0
sqlalchemy>=2.0.0
pydantic>=2.0.0
pydantic-settings>=2.0.0
# 根据数据库类型选择驱动
# psycopg2-binary>=2.9.0     # PostgreSQL
# pymysql>=1.1.0             # MySQL
# aiosqlite>=0.19.0          # SQLite async

# 开发依赖
ruff>=0.4.0
pyright>=1.1.350
pytest>=8.0.0
pytest-asyncio>=0.23.0
```

## 第八步：创建边界检查脚本

将 scripts/check_boundaries.py 从工具包模板复制到项目中。
此脚本自动发现 app/ 下的所有模块，检查：
1. 不允许跨模块直接导入 DAO
2. Service/Router 层不允许直接使用 db.query()
3. Router 层不允许直接导入 DAO

## 第九步：创建 Skills

将 add-module 和 entropy-review 的 SKILL.md 复制到项目的 .claude/skills/ 下。

## 第十步：创建根 CLAUDE.md

```markdown
# {项目名称}
{项目描述}

## 命令
- `ruff check . --fix`: lint 检查并自动修复
- `pyright`: 类型检查
- `pytest`: 运行所有测试
- `pytest app/{module}/tests/ -v`: 运行模块测试
- `pytest tests/flows/ -v`: 运行端到端流程测试
- `python scripts/check_boundaries.py`: 检查模块边界

## Skill 使用规则
- 需要创建新的业务模块时，必须使用 /add-module，不要手动创建模块目录结构
- 定期运行 /entropy-review 进行项目健康度审计
- 已有项目迁移使用 /migrate-project

## 架构规范

数据库访问严格分层：
- Model（model.py）：表结构、关联关系、状态流转规则、副作用定义
- DAO（dao.py）：数据库查询，继承 BaseDAO，所有查询基于 _base_query()
- Service（service.py）：业务逻辑，执行副作用，跨模块调用走 Service
- Router（router.py）：HTTP 接口，只调 Service

跨模块调用只允许 Service 之间互相调用，不要跨模块直接使用 DAO。

## 数据流规范

有状态流转的模型必须在 model.py 中定义：
- VALID_TRANSITIONS：合法的状态转换路径
- TRANSITION_SIDE_EFFECTS：每个转换触发的跨模块副作用

service.py 中通过 _side_effect_handlers 路由副作用到具体执行方法。
所有状态转换通过 transition_status() 统一入口执行。

## 业务流程
完整的业务操作流程记录在 tests/flows/ 中。
需要了解某个业务的完整流程时，阅读对应的 flow 测试文件。
添加新的跨模块业务流程时，在 tests/flows/ 中添加对应的流程测试。

## 添加新功能的步骤
1. 确定属于哪个模块，进入 app/xxx/
2. 读 model.py 了解数据结构、关联关系和状态规则
3. 读 dao.py 看有没有现成的查询方法
4. 在 service.py 中实现业务逻辑
5. 在 router.py 中暴露接口
6. 在模块 tests/ 中补单元测试
7. 如果涉及跨模块流程，在 tests/flows/ 中补流程测试
8. 运行 ruff check、pyright、pytest、check_boundaries.py 确认通过

## 工作流程
1. 改完代码后先运行 ruff check 和 pyright
2. 涉及数据库或业务逻辑的改动，必须运行 pytest
3. 如果没有覆盖当前改动的测试，先写测试再改代码

## 模块边界

每个模块的职责边界（负责/不负责/对外暴露）定义在该模块的 __init__.py 中。
这是唯一的定义位置，不要在其他地方重复。
以下决策表只记录有歧义的、讨论后做出的跨模块边界决策：

| 功能 | 归属模块 | 原因 |
|------|---------|------|
| （根据用户提供的模块信息填写已知的边界决策） |  |  |
```

## 第十一步：创建提交检查

### git pre-commit hook

创建 .git/hooks/pre-commit（git init 之后执行），内容：

```bash
#!/bin/bash
# 提交前自动检查

ERRORS=()

# 1. 模块边界检查
python scripts/check_boundaries.py > /dev/null 2>&1
if [ $? -ne 0 ]; then
    ERRORS+=("模块边界检查未通过，运行 python scripts/check_boundaries.py 查看详情")
fi

# 2. lint 检查
ruff check . --quiet > /dev/null 2>&1
if [ $? -ne 0 ]; then
    ERRORS+=("Lint 检查未通过，运行 ruff check . 查看详情")
fi

# 3. 类型检查
pyright --outputjson 2>/dev/null | python -c "
import json, sys
data = json.load(sys.stdin)
if data.get('summary', {}).get('errorCount', 0) > 0:
    sys.exit(1)
" 2>/dev/null
if [ $? -ne 0 ]; then
    ERRORS+=("类型检查未通过，运行 pyright 查看详情")
fi

# 4. 改了 model.py 必须有测试变更
CHANGED_MODELS=$(git diff --cached --name-only | grep "model\.py$")
if [ -n "$CHANGED_MODELS" ]; then
    CHANGED_TESTS=$(git diff --cached --name-only | grep "test_")
    if [ -z "$CHANGED_TESTS" ]; then
        ERRORS+=("修改了 model.py 但没有更新测试文件")
    fi
fi

# 5. 新模块必须有 __init__.py 和 CLAUDE.md
NEW_MODULES=$(git diff --cached --name-only --diff-filter=A | grep "^app/[a-z]*/model\.py$" | sed 's|/model\.py||')
for module in $NEW_MODULES; do
    if ! git diff --cached --name-only | grep -q "$module/__init__.py"; then
        ERRORS+=("新模块 $module 缺少 __init__.py 职责声明")
    fi
    if ! git diff --cached --name-only | grep -q "$module/CLAUDE.md"; then
        ERRORS+=("新模块 $module 缺少 CLAUDE.md")
    fi
done

# 6. 改了副作用定义必须改 service
SIDE_EFFECT_CHANGES=$(git diff --cached -U0 | grep "+.*TRANSITION_SIDE_EFFECTS")
if [ -n "$SIDE_EFFECT_CHANGES" ]; then
    SERVICE_CHANGES=$(git diff --cached --name-only | grep "service\.py$")
    if [ -z "$SERVICE_CHANGES" ]; then
        ERRORS+=("修改了 TRANSITION_SIDE_EFFECTS 但没有更新 service.py 的 handler")
    fi
fi

if [ ${#ERRORS[@]} -gt 0 ]; then
    echo "提交被拦截："
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  ✗ $err"
    done
    echo ""
    echo "修复后重新提交。如确认无需修改，使用 git commit --no-verify 跳过。"
    exit 1
fi

exit 0
```

设置可执行权限：
```bash
chmod +x .git/hooks/pre-commit
```

### Claude Code hook

在 .claude/settings.json 中添加提交前提醒：

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash -c 'INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r \".tool_input.command // empty\"); if echo \"$CMD\" | grep -qE \"^git commit\"; then echo \"提交前检查：\\n1. 修改了模块职责？→ 更新 __init__.py\\n2. 新增状态转换？→ 更新 VALID_TRANSITIONS + TRANSITION_SIDE_EFFECTS\\n3. 新增副作用？→ 添加 service.py handler\\n4. 发现新的坑？→ 更新模块 CLAUDE.md\\n5. 跨模块边界歧义？→ 更新根 CLAUDE.md 边界表\\n6. pytest 和 check_boundaries.py 是否通过\"; fi'"
          }
        ]
      }
    ]
  }
}
```

## 第十二步：验证

```bash
ruff check .
pyright
pytest
python scripts/check_boundaries.py
```

全部通过后执行 Git 初始化：

```bash
git init
git add .
git commit -m "feat: initialize project with standard architecture"
```

然后安装 pre-commit hook：
```bash
cp scripts/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## 第十三步：提示用户后续操作

告诉用户：
- 安装 pyright LSP 插件：`/plugin install pyright-lsp@claude-plugins-official`
- 后续添加新模块：`/add-module`
- 定期熵减审计（建议每两周）：`/entropy-review`
- 模块边界决策表在根 CLAUDE.md 中，遇到新的模糊边界时及时补充
- 提交时 pre-commit hook 会自动检查一致性，无需手动记忆
