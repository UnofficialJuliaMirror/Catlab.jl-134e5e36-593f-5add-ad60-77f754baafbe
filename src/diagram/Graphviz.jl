""" AST and pretty printer for Graphviz's DOT language.

This module does not provide bindings to the Graphviz library. For that, see
the GraphViz.jl package: https://github.com/Keno/GraphViz.jl

References:

- DOT grammar: http://www.graphviz.org/doc/info/lang.html
- DOT language guide: http://www.graphviz.org/pdf/dotguide.pdf
"""
module Graphviz
export Expression, Statement, Attributes, Graph, Digraph, Subgraph, Node, Edge,
  pprint

using DataStructures: OrderedDict
using Parameters

# AST
#####

abstract type Expression end
abstract type Statement <: Expression end

""" AST type for Graphviz's "HTML-like" node labels.

The HTML is represented as an atomic string, for now.
"""
struct Html
  content::String
end

const AttributeValue = Union{String,Html}
const Attributes = OrderedDict{Symbol,AttributeValue}

@with_kw struct Graph <: Expression
  name::String
  directed::Bool
  stmts::Vector{Statement}=Statement[]
  graph_attrs::Attributes=Attributes()
  node_attrs::Attributes=Attributes()
  edge_attrs::Attributes=Attributes()
end

Graph(name::String, stmts::Vector{Statement}; kw...) =
  Graph(; name=name, directed=false, stmts=stmts, kw...)
Graph(name::String, stmts::Vararg{Statement}; kw...) =
  Graph(; name=name, directed=false, stmts=collect(stmts), kw...)
Digraph(name::String, stmts::Vector{Statement}; kw...) =
  Graph(; name=name, directed=true, stmts=stmts, kw...)
Digraph(name::String, stmts::Vararg{Statement}; kw...) =
  Graph(; name=name, directed=true, stmts=collect(stmts), kw...)

@with_kw struct Subgraph <: Statement
  name::String="" # Subgraphs can be anonymous
  stmts::Vector{Statement}=Statement[]
  graph_attrs::Attributes=Attributes()
  node_attrs::Attributes=Attributes()
  edge_attrs::Attributes=Attributes()
end

Subgraph(stmts::Vector{Statement}; kw...) = Subgraph(; stmts=stmts, kw...)
Subgraph(stmts::Vararg{Statement}; kw...) = Subgraph(; stmts=collect(stmts), kw...)
Subgraph(name::String, stmts::Vector{Statement}; kw...) =
  Subgraph(; name=name, stmts=stmts, kw...)
Subgraph(name::String, stmts::Vararg{Statement}; kw...) =
  Subgraph(; name=name, stmts=collect(stmts), kw...)

@with_kw struct Node <: Statement
  name::String
  attrs::Attributes=Attributes()
end
Node(name::String; attrs...) = Node(name, Attributes(attrs))

@with_kw struct Edge <: Statement
  src::String
  src_port::String=""
  src_anchor::String=""
  tgt::String
  tgt_port::String=""
  tgt_anchor::String=""
  attrs::Attributes=Attributes()
end
Edge(src::String, tgt::String; attrs...) =
  Edge(src=src, tgt=tgt, attrs=Attributes(attrs))
Edge(src::String, src_port::String, tgt::String, tgt_port::String; attrs...) =
  Edge(src=src, src_port=src_port, tgt=tgt, tgt_port=tgt_port, attrs=Attributes(attrs))

# Pretty-print
##############

""" Pretty-print the Graphviz expression.
"""
pprint(expr::Expression) = pprint(STDOUT, expr)
pprint(io::IO, expr::Expression) = pprint(io, expr, 0)

function pprint(io::IO, graph::Graph, n::Int)
  indent(io, n)
  print(io, graph.directed ? "digraph " : "graph ")
  print(io, graph.name)
  println(io, " {")
  pprint_attrs(io, graph.graph_attrs, n+2; pre="graph", post=";\n")
  pprint_attrs(io, graph.node_attrs, n+2; pre="node", post=";\n")
  pprint_attrs(io, graph.edge_attrs, n+2; pre="edge", post=";\n")
  for stmt in graph.stmts
    pprint(io, stmt, n+2, directed=graph.directed)
    println(io)
  end
  indent(io, n)
  println(io, "}")
end

function pprint(io::IO, subgraph::Subgraph, n::Int; directed::Bool=false)
  indent(io, n)
  if isempty(subgraph.name)
    println(io, "{")
  else
    print(io, "subgraph ")
    print(io, subgraph.name)
    println(io, " {")
  end
  pprint_attrs(io, subgraph.graph_attrs, n+2; pre="graph", post=";\n")
  pprint_attrs(io, subgraph.node_attrs, n+2; pre="node", post=";\n")
  pprint_attrs(io, subgraph.edge_attrs, n+2; pre="edge", post=";\n")
  for stmt in subgraph.stmts
    pprint(io, stmt, n+2, directed=directed)
    println(io)
  end
  indent(io, n)
  print(io, "}")
end

function pprint(io::IO, node::Node, n::Int; directed::Bool=false)
  indent(io, n)
  print(io, node.name)
  pprint_attrs(io, node.attrs)
  print(io, ";")
end

function pprint(io::IO, edge::Edge, n::Int; directed::Bool=false)
  indent(io, n)
  
  # Source
  print(io, edge.src)
  print(io, isempty(edge.src_port) ? "" : ":")
  print(io, edge.src_port)
  print(io, isempty(edge.src_anchor) ? "" : ":")
  print(io, edge.src_anchor)
  
  # Edge
  print(io, directed ? " -> " : " -- ")
  
  # Target
  print(io, edge.tgt)
  print(io, isempty(edge.tgt_port) ? "" : ":")
  print(io, edge.tgt_port)
  print(io, isempty(edge.tgt_anchor) ? "" : ":")
  print(io, edge.tgt_anchor)
  
  pprint_attrs(io, edge.attrs)
  print(io, ";")
end

function pprint_attrs(io::IO, attrs::Attributes, n::Int=0;
                      pre::String="", post::String="")
  if !isempty(attrs)
    indent(io, n)
    print(io, pre)
    print(io, " [")
    for (i, (key, value)) in enumerate(attrs)
      if (i > 1) print(io, ",") end
      print(io, key)
      print(io, "=")
      pprint_attr_value(io, value)
    end
    print(io, "]")
    print(io, post)
  end
end

function pprint_attr_value(io::IO, value::String)
  print(io, "\"")
  print(io, value)
  print(io, "\"")
end
function pprint_attr_value(io::IO, value::Html)
  print(io, "<")
  print(io, value.content)
  print(io, ">")
end

indent(io::IO, n::Int) = print(io, " "^n)

end