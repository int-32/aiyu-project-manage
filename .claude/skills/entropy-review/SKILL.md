---
name: entropy-review
description: >
  项目熵减审计。检查代码一致性、CLAUDE.md 准确性、数据流完整性、
  死代码、测试健康度。当用户说"熵减"、"项目审计"、"检查项目健康度"时使用。
disable-model-invocation: true
---

# 熵减审计

执行以下检查，将结果写入 docs/entropy-review-{YYYY-MM-DD}.md。
只生成报告和建议，不直接修改任何文件，等用户确认后再执行修改。

## 1. 自动化工具检查

```bash
echo "=== Ruff Check ==="
ruff check .

echo "=== Pyright ==="
pyright

echo "=== Boundary Check ==="
python scripts/check_boundaries.py

echo "=== Tests ==="
pytest --tb=short -q
```

记录每项的通过/失败状态和问题数量。

## 2. CLAUDE.md 一致性

阅读项目根目录和所有 app/*/CLAUDE.md，对照实际代码检查：

- [ ] 根 CLAUDE.md 中的命令是否都能正常运行
- [ ] 根 CLAUDE.md 的模块边界表是否需要更新（有没有新出现的跨模块歧义未记录）
- [ ] 根 CLAUDE.md 的模块边界表中是否有冗余条目（已在 __init__.py 中明确的无需重复）
- [ ] 模块 CLAUDE.md 中的数据流描述是否与 model.py 中的 TRANSITION_SIDE_EFFECTS 一致
- [ ] 模块 CLAUDE.md 中是否有重复 __init__.py 职责声明的内容（应删除）
- [ ] "容易犯的错误" 段落是否需要补充
- [ ] 有没有 CLAUDE.md 中的规则已通过测试或 lint 保障（可以删除减少噪音）

## 3. 模块结构一致性

检查所有 app/*/ 模块：

- [ ] 每个模块是否都有 __init__.py 且包含职责声明（负责/不负责/对外暴露）
- [ ] 职责声明是否只在 __init__.py 中定义（不在 CLAUDE.md 中重复）
- [ ] 每个模块是否都有 CLAUDE.md（只含数据流和容易犯的错误，不含职责）
- [ ] 每个 dao.py 是否都继承 BaseDAO 并使用 _base_query()
- [ ] 每个 service.py 是否有直接的 db.query() / session.query() 调用（不应该有）
- [ ] model.py 中的 relationship 定义是否完整
- [ ] 模块之间的依赖方向是否一致（只有 service → service）

## 4. 数据流完整性

对每个有状态流转的模块：

- [ ] Model 中的 VALID_TRANSITIONS 是否覆盖了所有实际使用的状态
- [ ] TRANSITION_SIDE_EFFECTS 中的每个副作用是否在 Service 的 _side_effect_handlers 中有对应 handler
- [ ] 有没有 Service 中存在的 handler 但 Model 中未定义的副作用（死代码）
- [ ] 副作用引用的其他模块 Service 方法是否仍然存在
- [ ] test_data_flow.py 是否覆盖了所有定义的状态转换

对每个跨模块流程：

- [ ] tests/flows/ 中是否有对应的端到端测试
- [ ] 流程测试是否覆盖了正常路径和主要异常路径
- [ ] 流程中涉及的模块是否在根 CLAUDE.md 的边界决策表中有记录

## 5. 死代码检测

```bash
echo "=== 未使用的 Import ==="
ruff check . --select F401

echo "=== 未使用的变量 ==="
ruff check . --select F841

echo "=== TODO/FIXME/HACK ==="
rg "TODO|FIXME|HACK" --type py -n
```

额外检查：
- 未被任何 router 注册的 Service 方法
- 未被任何测试覆盖的副作用 handler
- tests/factories.py 中存在但对应模型已不存在的工厂方法

## 6. 测试健康度

- [ ] 有没有被 @pytest.mark.skip 跳过的测试，原因是否还成立
- [ ] 有没有不稳定的测试（时而过时而不过）
- [ ] 哪些模块缺少 test_data_flow.py（有状态流转但没有数据流测试）
- [ ] 哪些核心流程缺少 tests/flows/ 中的端到端测试
- [ ] factories.py 中的工厂方法是否与模型定义一致

## 7. 生成报告

按优先级分类汇总：

### 必须修复（直接影响 Claude 工作准确性）
- 边界违规
- CLAUDE.md 与代码不一致
- 副作用定义与 handler 不同步
- 结构不一致的模块

### 建议修复（提升代码质量和 Claude 准确率）
- 缺失的数据流测试
- 缺失的端到端流程测试
- 死代码清理
- TODO 清理

### 观察项（暂不需要行动）
- 可能需要拆分的大文件（单文件超过 300 行）
- 可能需要新增的模块边界决策
- 可能需要新增的副作用定义

报告末尾附上建议的下一步行动清单。
