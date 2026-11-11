"""Build static analysis interfaces without importing or executing a library."""
import ast


def docstring(body):
    if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
        if isinstance(body[0].value.value, str):
            return [body[0]]
    return []


def safe_default(value):
    try:
        ast.literal_eval(value)
        return value
    except (ValueError, TypeError):
        return ast.Constant(value=Ellipsis)


def function(node):
    node.body = docstring(node.body) + [ast.Expr(value=ast.Constant(value=Ellipsis))]
    node.decorator_list = [item for item in node.decorator_list if ast.unparse(item).split('.')[-1]
                           in {'overload', 'staticmethod', 'classmethod', 'property', 'abstractmethod',
                               'final', 'setter', 'deleter'}]
    node.args.defaults = [safe_default(value) for value in node.args.defaults]
    node.args.kw_defaults = [safe_default(value) if value else None for value in node.args.kw_defaults]
    if node.returns is None:
        node.returns = ast.Constant(value=None) if node.name == '__init__' else ast.Name(id='_NotebookAny')
    return node


def assignment(node):
    if isinstance(node, ast.AnnAssign):
        node.value = ast.Constant(value=Ellipsis) if node.value else None
        return node
    if any(isinstance(target, (ast.Attribute, ast.Subscript)) for target in node.targets):
        return None
    if any(isinstance(item, ast.Call) for item in ast.walk(node.value)):
        return None
    if any(isinstance(target, ast.Name) and target.id == '__all__' for target in node.targets):
        return node if isinstance(node.value, (ast.List, ast.Tuple)) else None
    if isinstance(node.value, (ast.Name, ast.Attribute, ast.Subscript, ast.BinOp, ast.Constant)):
        return node
    return None


def statements(body):
    result = docstring(body)
    for node in body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            result.append(function(node))
        elif isinstance(node, ast.ClassDef):
            node.body = statements(node.body) or [ast.Expr(value=ast.Constant(value=Ellipsis))]
            node.decorator_list = [item for item in node.decorator_list
                                   if ast.unparse(item).split('.')[-1] in {'dataclass', 'final'}]
            result.append(node)
        elif isinstance(node, ast.ImportFrom):
            if node.module != '__future__':
                for name in node.names:
                    if name.name != '*' and name.asname is None:
                        name.asname = name.name
            result.append(node)
        elif isinstance(node, ast.Import):
            result.append(node)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = assignment(node)
            if value:
                result.append(value)
        elif isinstance(node, ast.If):
            if isinstance(node.test, ast.Name) and node.test.id == 'TYPE_CHECKING':
                result.extend(statements(node.body))
            elif '__name__' not in ast.unparse(node.test):
                result.extend(statements(node.body))
                result.extend(statements(node.orelse))
        elif isinstance(node, ast.Try):
            result.extend(statements(node.body))
            for handler in node.handlers:
                result.extend(statements(handler.body))
    return result


def convert(source):
    tree = ast.parse(source)
    tree.body = statements(tree.body)
    # Unknown implementation return types stay unknown instead of becoming None.
    index = len(docstring(tree.body))
    while index < len(tree.body) and isinstance(tree.body[index], ast.ImportFrom) and tree.body[index].module == '__future__':
        index += 1
    tree.body.insert(index, ast.ImportFrom(module='typing', names=[ast.alias(name='Any', asname='_NotebookAny')], level=0))
    ast.fix_missing_locations(tree)
    source = '# Generated static documentation interface; not runtime code.\n' + ast.unparse(tree) + '\n'
    compile(source, '<library-interface>', 'exec')
    return source
