// Expand <sc-for>/<sc-if> and {{holes}} in a design-canvas board using its own renderVals() data.
// Usage: node tools/ui/flatten_dc.mjs Board.dc.html > flat.html
import { readFileSync } from "node:fs";

const src = readFileSync(process.argv[2], "utf8");
const script = src.match(/<script type="text\/x-dc"[^>]*>([\s\S]*?)<\/script>/);
let vals = {};
if (script) {
  class DCLogic {}
  const Component = new Function("DCLogic", script[1] + "\nreturn Component;")(DCLogic);
  vals = new Component().renderVals();
}
const get = (path, scope) => path.split(".").reduce((o, k) => (o == null ? o : o[k]), { ...vals, ...scope });
const fill = (s, scope) => s.replace(/\{\{\s*([\w.]+)\s*\}\}/g, (_, p) => String(get(p, scope) ?? ""));

function expand(html, scope = {}) {
  html = html.replace(/<sc-for list="\{\{(\w+)\}\}" as="(\w+)"[^>]*>([\s\S]*?)<\/sc-for>/g, (_, list, as, body) =>
    (get(list, scope) || []).map((item) => expand(body, { ...scope, [as]: item })).join(""));
  html = html.replace(/<sc-if value="\{\{([\w.]+)\}\}"[^>]*>([\s\S]*?)<\/sc-if>/g, (_, p, body) =>
    get(p, scope) ? expand(body, scope) : "");
  return fill(html, scope);
}
process.stdout.write(expand(src));
