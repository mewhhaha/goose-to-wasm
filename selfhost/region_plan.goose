import model;

// Region counts describe simultaneous lifetimes, independent of image length.
// Every recursive edge within one call component must release its temporaries.
struct RegionFunction {
    node: i64 = -1, own: i64 = 0, need: i64 = 0, entry: bool = false,
    index: i64 = -1, low: i64 = -1, component: i64 = -1,
}
struct RegionCall { caller: i64, callee: i64, live: i64, node: i64 = -1 }
struct RegionGraph {
    functions: RegionFunction[>..]&, calls: RegionCall[>..]&, stack: i64[>..]&, members: i64[>..]&,
    serial: i64 = 0, components: i64 = 0,
}
fn region_diagnose(p: Program&, node: i64, message: u8[:]) {
    var token = -1; if node >= 0 && node < p.nodes.len { token = p.nodes[node].token; }
    diagnose(p, token, message);
}
fn region_sum(p: Program&, node: i64, left: i64, right: i64) -> i64 {
    if left < 0 || right < 0 || left > 9223372036854775807 - right {
        region_diagnose(p, node, "data-region count is out of range"); return 0;
    }
    return left + right;
}
recursive fn region_component(p: Program&, graph: RegionGraph&, function: i64) {
    let serial = graph.serial; graph.serial += 1;
    graph.functions[function].index = serial; graph.functions[function].low = serial;
    graph.functions[function].component = -2; graph.stack.push(function);
    let call_count = graph.calls.len;
    for index in 0..call_count {
        let call = graph.calls[index]; if call.caller != function { continue; }
        if call.callee < 0 || call.callee >= graph.functions.len {
            region_diagnose(p, call.node, "region call has no function plan"); continue;
        }
        if graph.functions[call.callee].index < 0 {
            region_component(p, graph, call.callee);
            if graph.functions[call.callee].low < graph.functions[function].low { graph.functions[function].low = graph.functions[call.callee].low; }
        } else if graph.functions[call.callee].component == -2 && graph.functions[call.callee].index < graph.functions[function].low {
            graph.functions[function].low = graph.functions[call.callee].index;
        }
    }
    if graph.functions[function].low != graph.functions[function].index { return; }
    let component = graph.components; graph.components += 1; let mark = graph.members.len;
    loop {
        let member = graph.stack.pop(); graph.functions[member].component = component; graph.members.push(member);
        if member == function { break; }
    }
    let end = graph.members.len; var bound = 0;
    for index in mark..end {
        let member = graph.members[index]; if graph.functions[member].own > bound { bound = graph.functions[member].own; }
        for call in graph.calls {
            if call.caller != member || call.callee < 0 || call.callee >= graph.functions.len { continue; }
            if graph.functions[call.callee].component == component {
                if call.live != 0 { region_diagnose(p, call.node, "recursive call retains transient data regions"); }
            } else {
                let required = region_sum(p, call.node, call.live, graph.functions[call.callee].need);
                if required > bound { bound = required; }
            }
        }
    }
    for index in mark..end { graph.functions[graph.members[index]].need = bound; }
    graph.members.resize(mark);
}
fn region_bound(p: Program&, graph: RegionGraph&, globals: i64) -> i64 {
    graph.serial = 0; graph.components = 0; graph.stack.clear(); graph.members.clear();
    for item, index in graph.functions {
        graph.functions[index].index = -1; graph.functions[index].low = -1;
        graph.functions[index].component = -1; graph.functions[index].need = 0;
    }
    let count = graph.functions.len;
    for index in 0..count { if graph.functions[index].index < 0 { region_component(p, graph, index); } }
    var bound = 0;
    for item in graph.functions { if item.entry && item.need > bound { bound = item.need; } }
    return region_sum(p, -1, bound, globals);
}
