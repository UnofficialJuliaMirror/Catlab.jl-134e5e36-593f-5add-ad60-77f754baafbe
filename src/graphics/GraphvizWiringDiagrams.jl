""" Draw wiring diagrams (aka string diagrams) using Graphviz.
"""
module GraphvizWiringDiagrams
export to_graphviz

import ...Doctrines: HomExpr
using ...WiringDiagrams, ...WiringDiagrams.WiringDiagramSerialization
import ..Graphviz
import ..Graphviz: to_graphviz

# Constants and data types
##########################

# Default Graphviz font. Reference: http://www.graphviz.org/doc/fontfaq.txt
const default_font = "Serif"

# Default graph, node, edge, and cell attributes.
const default_graph_attrs = Graphviz.Attributes(
  :fontname => default_font,
)
const default_node_attrs = Graphviz.Attributes(
  :fontname => default_font,
  :shape => "none",
  :width => "0",
  :height => "0",
  :margin => "0",
)
const default_edge_attrs = Graphviz.Attributes(
  :arrowsize => "0.5",
  :fontname => default_font,
)
const default_cell_attrs = Graphviz.Attributes(
  :border => "1",
  :cellpadding => "4",
)

struct GraphvizBox
  stmts::Vector{Graphviz.Statement} # Usually Graphviz.Node
  input_ports::Vector{Graphviz.NodeID}
  output_ports::Vector{Graphviz.NodeID}
end

# Conversion
############

""" Render a wiring diagram using Graphviz.

The input `f` can also be a morphism expression, which is converted into a
wiring diagram.

# Arguments
- `graph_name="G"`: name of Graphviz digraph
- `direction=:vertical`: layout direction.
  Either `:vertical` (top to bottom) or `:horizontal` (left to right).
- `node_labels=true`: whether to label the nodes
- `labels=false`: whether to label the edges
- `label_attr=:label`: what kind of edge label to use (if `labels` is true).
  One of `:label`, `:xlabel`, `:headlabel`, or `:taillabel`.
- `port_size="24"`: minimum size of ports on box, in points
- `junction_size="0.05"`: size of junction nodes, in inches
- `outer_ports=true`: whether to display the outer box's input and output ports.
  If disabled, no incoming or outgoing wires will be shown either!
- `anchor_outer_ports=true`: whether to enforce ordering of the outer box's
  input and output, i.e., ordering of the incoming and outgoing wires
- `graph_attrs=default_graph_attrs`: top-level graph attributes
- `node_attrs=default_node_attrs`: top-level node attributes
- `edge_attrs=default_edge_attrs`: top-level edge attributes
- `cell_attrs=default_cell_attrs`: main cell attributes in node HTML-like label
"""
function to_graphviz(f::WiringDiagram;
    graph_name::String="G", direction::Symbol=:vertical,
    node_labels::Bool=true, labels::Bool=false, label_attr::Symbol=:label,
    port_size::String="24", junction_size::String="0.05",
    outer_ports::Bool=true, anchor_outer_ports::Bool=true,
    graph_attrs::Graphviz.Attributes=Graphviz.Attributes(),
    node_attrs::Graphviz.Attributes=Graphviz.Attributes(),
    edge_attrs::Graphviz.Attributes=Graphviz.Attributes(),
    cell_attrs::Graphviz.Attributes=Graphviz.Attributes())::Graphviz.Graph
  @assert direction in (:vertical, :horizontal)
  @assert label_attr in (:label, :xlabel, :headlabel, :taillabel)
  vertical = direction == :vertical

  # State variables.
  stmts = Graphviz.Statement[]
  port_map = Dict{Port,Graphviz.NodeID}()
  update_port_map! = (v::Int, kind::PortKind, node_ids) -> begin
    for (i, node_id) in enumerate(node_ids)
      port_map[Port(v,kind,i)] = node_id
    end
  end
  
  # Invisible nodes for incoming and outgoing wires.
  if outer_ports
    gv_box = graphviz_outer_box(f; anchor=anchor_outer_ports, vertical=vertical)
    append!(stmts, gv_box.stmts)
    update_port_map!(input_id(f), OutputPort, gv_box.input_ports)
    update_port_map!(output_id(f), InputPort, gv_box.output_ports)
  end
  
  # Visible nodes for boxes.
  cell_attrs = merge(default_cell_attrs, cell_attrs)
  for v in box_ids(f)
    gv_box = graphviz_box(box(f,v), box_id([v]),
      vertical=vertical, labels=node_labels, port_size=port_size,
      junction_size=junction_size, cell_attrs=cell_attrs)
    append!(stmts, gv_box.stmts)
    update_port_map!(v, InputPort, gv_box.input_ports)
    update_port_map!(v, OutputPort, gv_box.output_ports)
  end
  
  # Edges.
  for (i, wire) in enumerate(wires(f))
    source, target = wire.source, wire.target
    if !(haskey(port_map, source) && haskey(port_map, target))
      continue
    end
    # Use the port value to label the wire. We take the source port.
    # In most wiring diagrams, the source and target ports should yield the
    # same label, but that is not guaranteed. An advantage of choosing the
    # source port over the target port is that it will carry the
    # "more specific" type when implicit conversions are allowed.
    port = port_value(f, source)
    attrs = Graphviz.Attributes(
      :id => wire_id(Int[], i),
      :comment => edge_label(port),
    )
    if labels
      attrs[label_attr] = edge_label(port)
    end
    edge = Graphviz.Edge(port_map[source], port_map[target]; attrs...)
    push!(stmts, edge)
  end
  
  # Graph.
  graph_attrs = merge(graph_attrs, Graphviz.Attributes(
    :rankdir => vertical ? "TB" : "LR"
  ))
  Graphviz.Digraph(graph_name, stmts;
    graph_attrs=merge(default_graph_attrs, graph_attrs),
    node_attrs=merge(default_node_attrs, node_attrs),
    edge_attrs=merge(default_edge_attrs, edge_attrs))
end

function to_graphviz(f::HomExpr; kw...)::Graphviz.Graph
  to_graphviz(to_wiring_diagram(f); kw...)
end

""" Graphviz box for a generic box.
"""
function graphviz_box(box::AbstractBox, node_id::String;
    vertical::Bool=true, labels::Bool=true, port_size::String="0",
    cell_attrs::Graphviz.Attributes=Graphviz.Attributes(), kw...)
  # Main node.
  nin, nout = length(input_ports(box)), length(output_ports(box))
  text_label = labels ? node_label(box.value) : ""
  html_label = node_html_label(nin, nout, text_label;
    vertical=vertical, port_size=port_size, attrs=cell_attrs)
  # Note: The `id` attribute is included in the Graphviz output but is not used
  # internally by Graphviz. It is for use by downstream applications.
  # Reference: http://www.graphviz.org/doc/info/attrs.html#d:id
  node = Graphviz.Node(node_id,
    id = node_id,
    comment = node_label(box.value),
    label = html_label,
  )
  
  # Input and output ports.
  graphviz_port = (kind::PortKind, port::Int) -> begin
    Graphviz.NodeID(node_id, port_name(kind, port), port_anchor(kind, vertical))
  end
  inputs = [ graphviz_port(InputPort, i) for i in 1:nin ]
  outputs = [ graphviz_port(OutputPort, i) for i in 1:nout ]
  
  GraphvizBox([node], inputs, outputs)
end

""" Graphviz box for a junction.
"""
function graphviz_box(junction::Junction, node_id::String;
    junction_size::String="0", kw...)
  node = Graphviz.Node(node_id,
    id = node_id,
    comment = "junction",
    label = "",
    shape = "circle",
    style = "filled",
    fillcolor = "black",
    width = junction_size,
    height = junction_size,
  )
  inputs = repeat([Graphviz.NodeID(node_id)], junction.ninputs)
  outputs = repeat([Graphviz.NodeID(node_id)], junction.noutputs)
  GraphvizBox([node], inputs, outputs)
end

""" Create "HTML-like" node label for a box.
"""
function node_html_label(nin::Int, nout::Int, text_label::String;
    vertical::Bool=true, port_size::String="0",
    attrs::Graphviz.Attributes=Graphviz.Attributes())::Graphviz.Html
  if vertical
    Graphviz.Html("""
      <TABLE BORDER="0" CELLPADDING="0" CELLSPACING="0">
      <TR><TD>$(ports_horizontal_html_label(InputPort,nin,port_size))</TD></TR>
      <TR><TD $(html_attributes(attrs))>$(escape_html(text_label))</TD></TR>
      <TR><TD>$(ports_horizontal_html_label(OutputPort,nout,port_size))</TD></TR>
      </TABLE>""")
  else
    Graphviz.Html("""
      <TABLE BORDER="0" CELLPADDING="0" CELLSPACING="0">
      <TR>
      <TD>$(ports_vertical_html_label(InputPort,nin,port_size))</TD>
      <TD $(html_attributes(attrs))>$(escape_html(text_label))</TD>
      <TD>$(ports_vertical_html_label(OutputPort,nout,port_size))</TD>
      </TR>
      </TABLE>""")
  end
end

""" Create horizontal "HTML-like" label for the input or output ports of a box.
"""
function ports_horizontal_html_label(kind::PortKind, nports::Int,
    port_size::String="0")::Graphviz.Html
  cols = if nports > 0
    join("""<TD HEIGHT="0" WIDTH="$port_size" PORT="$(port_name(kind,i))"></TD>"""
         for i in 1:nports)
  else
    """<TD HEIGHT="0" WIDTH="$port_size"></TD>"""
  end
  Graphviz.Html("""
    <TABLE BORDER="0" CELLPADDING="0" CELLSPACING="0"><TR>$cols</TR></TABLE>""")
end

""" Create vertical "HTML-like" label for the input or output ports of a box.
"""
function ports_vertical_html_label(kind::PortKind, nports::Int,
    port_size::String="0")::Graphviz.Html
  rows = if nports > 0
    join("""<TR><TD HEIGHT="$port_size" WIDTH="0" PORT="$(port_name(kind,i))"></TD></TR>"""
         for i in 1:nports)
  else
    """<TR><TD HEIGHT="$port_size" WIDTH="0"></TD></TR>"""
  end
  Graphviz.Html("""
    <TABLE BORDER="0" CELLPADDING="0" CELLSPACING="0">$rows</TABLE>""")
end

""" Graphviz box for the outer box of a wiring diagram.
"""
function graphviz_outer_box(f::WiringDiagram;
    anchor::Bool=true, vertical::Bool=true)
  # Subgraphs containing invisible nodes.
  stmts = Graphviz.Statement[]
  ninputs, noutputs = length(input_ports(f)), length(output_ports(f))
  if ninputs > 0
    push!(stmts, graphviz_outer_ports(input_id(f), InputPort, ninputs;
      anchor=anchor, vertical=vertical))
  end
  if noutputs > 0
    push!(stmts, graphviz_outer_ports(output_id(f), OutputPort, noutputs;
      anchor=anchor, vertical=vertical))
  end
  
  # Input and output ports.
  graphviz_port = (port::Port) -> Graphviz.NodeID(
    port_node_name(port.box, port.port),
    port_anchor(port.kind, vertical)
  )
  inputs = [ graphviz_port(Port(input_id(f), OutputPort, i)) for i in 1:ninputs ]
  outputs = [ graphviz_port(Port(output_id(f), InputPort, i)) for i in 1:noutputs ]
  
  GraphvizBox(stmts, inputs, outputs)
end

""" Create invisible nodes for the input or output ports of an outer box.
"""
function graphviz_outer_ports(v::Int, kind::PortKind, nports::Int;
    anchor::Bool=true, vertical::Bool=true)::Graphviz.Subgraph
  @assert nports > 0
  dir = vertical ? "LR" : "TB"
  port_width = "$(round(24/72,digits=3))" # port width in inches
  nodes = [ port_node_name(v, i) for i in 1:nports ]
  stmts = Graphviz.Statement[
    Graphviz.Node(nodes[i], id=port_name(kind, i)) for i in 1:nports
  ]
  if anchor
    push!(stmts, Graphviz.Edge(nodes))
  end
  Graphviz.Subgraph(
    stmts,
    graph_attrs=Graphviz.Attributes(
      :rank => kind == InputPort ? "source" : "sink",
      :rankdir => dir,
    ),
    node_attrs=Graphviz.Attributes(
      :style => "invis",
      :shape => "none",
      :label => "",
      :width => dir == "LR" ? port_width : "0",
      :height => dir == "TB" ? port_width : "0",
    ),
    edge_attrs=Graphviz.Attributes(
      :style => "invis",
    ),
  )
end
port_node_name(v::Int, port::Int) = string(box_id([v]), "p", port)

""" Graphviz anchor for port.
"""
function port_anchor(kind::PortKind, vertical::Bool)
  if vertical
    kind == InputPort ? "n" : "s"
  else
    kind == InputPort ? "w" : "e"
  end
end

""" Create a label for the main content of a box.
"""
node_label(box_value::Any) = string(box_value)
node_label(::Nothing) = ""

""" Create a label for an edge.
"""
edge_label(port_value::Any) = string(port_value)
edge_label(::Nothing) = ""

""" Encode attributes for Graphviz HTML-like labels.
"""
function html_attributes(attrs::Graphviz.Attributes)::String
  join(["$(uppercase(string(k)))=\"$v\"" for (k,v) in attrs], " ")
end

""" Escape special HTML characters: &, <, >, ", '

Borrowed from HttpCommon package: https://github.com/JuliaWeb/HttpCommon.jl
"""
function escape_html(s::AbstractString)
  s = replace(s, "&" => "&amp;")
  s = replace(s, "\"" => "&quot;")
  s = replace(s, "'" => "&#39;")
  s = replace(s, "<" => "&lt;")
  s = replace(s, ">" => "&gt;")
  return s
end

end
