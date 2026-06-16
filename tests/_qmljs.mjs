import { readFileSync } from 'fs';
import { dirname, resolve } from 'path';
const _cache = {};
export function loadQmlJs(absPath) {
  if (_cache[absPath]) return _cache[absPath];
  let src = readFileSync(absPath, 'utf8');
  const dir = dirname(absPath);
  const deps = {};
  src = src.replace(/^[ \t]*\.import[ \t]+["']([^"']+)["'][ \t]+as[ \t]+(\w+)[ \t]*$/gm, (_m, rel, name) => {
    deps[name] = loadQmlJs(resolve(dir, rel));
    return '';
  });
  src = src.replace(/^[ \t]*\.pragma[ \t]+\w+[ \t]*$/gm, '');
  // Only collect TOP-LEVEL declarations (column 0, no leading whitespace) so we
  // don't try to export function-local `var`s that aren't in scope at return.
  const fnNames = [...src.matchAll(/^function[ \t]+([A-Za-z_$][\w$]*)/gm)].map(m => m[1]);
  const varNames = [...src.matchAll(/^var[ \t]+([A-Za-z_$][\w$]*)/gm)].map(m => m[1]);
  const names = [...new Set([...fnNames, ...varNames])];
  const depNames = Object.keys(deps);
  const factory = new Function(...depNames, `${src}\n; return { ${names.join(', ')} };`);
  const mod = factory(...depNames.map(n => deps[n]));
  _cache[absPath] = mod;
  return mod;
}
