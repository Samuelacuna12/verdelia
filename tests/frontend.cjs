const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(__dirname + '/../dist/app.js', 'utf8').split("window.addEventListener('hashchange'")[0];
const context = vm.createContext({
  window: {VERDELIA_CONFIG: {}, addEventListener() {}},
  localStorage: {getItem() {return ''}},
  document: {addEventListener() {}}, Intl, Date, console, setTimeout, clearTimeout, setInterval() {},
});
vm.runInContext(source, context);
const run = code => vm.runInContext(code, context);
assert.equal(run("dateKey('2026-11-02T02:00:00Z')"), '2026-11-01', 'Colombian business day');
assert.equal(run("dateKey('2026-11-02T05:00:00Z')"), '2026-11-02', 'Midnight boundary');
assert.equal(run("factor({unit:'kg'},'lb')"), 0.5);
assert.equal(run("factor({unit:'kg'},'g')"), 0.001);
const result = run(`financial({sales:[{type:'sale',total:12000,cost:7000},{type:'refund',total:-6000,cost:-3000}],cash:[{kind:'expense',amount:-500},{kind:'purchase',amount:-15000},{kind:'deposit',amount:20000}],stock_moves:[{reason:'loss',quantity:-1,unit_cost:1000}]})`);
assert.equal(result.revenue, 6000);
assert.equal(result.profit, 500, 'Purchases and owner deposits are not operating profit');
assert.equal(result.refunds, 6000);
assert.equal(result.count, 1);
assert.equal(run("csvCell('=SUM(A1)')"), '"\'=SUM(A1)"');
assert.equal(run("esc('<script>')"), '&lt;script&gt;');
assert.equal(run("groupDays([{created_at:'2026-11-02T02:00:00Z',total:3000},{created_at:'2026-11-01T18:00:00Z',total:-1000}])['2026-11-01']"), 2000);
console.log('PASS: Colombia dates, kg/lb/g, profit/refunds/losses, grouping, escaping and CSV');

assert.equal(run("unitNames.kg"),'Kilos disponibles');
assert.equal(run("priceMeasures('kg')[1][0]"),'lb');

assert.equal(run("suggestedSalePrice(3000,'lb','lb','kg',30)"),3900);
assert.equal(run("suggestedSalePrice(3000,'lb','lb','kg',40)"),4200);
assert.equal(run("suggestedSalePrice(3000,'lb','lb','kg',50)"),4500);
assert.equal(run("suggestedSalePrice(3000,'lb','kg','kg',30)"),7800);
assert.equal(run("suggestedSalePrice(5000,'kg','lb','kg',35)"),3375);
assert.equal(run("suggestedSalePrice(1200,'und','und','und',50)"),1800);
console.log('PASS: suggested prices use markup on cost, custom percentages, and selected measures');

for(const category of ['Frutas','Verduras','Minimarket','Lácteos','Limpieza','Golosinas','Arepas y empanadas','Jugos','Congelados'])assert.equal(run('categories.includes('+JSON.stringify(category)+')'),true);
console.log('PASS: all agreed product categories are available');
