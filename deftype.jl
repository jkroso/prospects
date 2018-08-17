@require "github.com/MikeInnes/MacroTools.jl" => MacroTools @capture @match
using Base.Iterators

@eval macro $:struct(e::Expr) deftype(e, false) end
@eval macro $:mutable(e::Expr) deftype(e, true) end

deftype(e::Expr, mutable) = begin
  @capture(e, (call_ <: super_)|call_)
  @capture(call, (name_{curlies__}|name_)(args__))
  curlies = curlies == nothing ? [] : curlies
  T = isempty(curlies) ? name : :($name{$(curlies...)})
  def = Expr(:struct, mutable, :($T <: $(super ≡ nothing ? Any : super)),
                               quote $(map(tofield, args)...) end)
  out = quote Base.@__doc__($(esc(def))) end
  for i in length(args):-1:1
    arg = args[i]
    isoptional(arg) || break
    params = map(tofield, take(args, i - 1))
    values = [map(tosymbol, params)..., tovalue(arg)]
    push!(out.args, esc(:($T($(params...)) where {$(curlies...)} = $T($(values...)))))
  end
  if !mutable
    fields = map(x->x|>tofield|>tosymbol, args)
    push!(out.args, esc(defhash(T, curlies, fields)),
                    esc(defequals(T, curlies, fields)))
  end
  push!(out.args, nothing)
  out
end

isoptional(e) = @capture(e, (_=_)|(_::_=_)|(_::Union{Missing,_})|(_::Union{_,Missing}))

# a=1 → a::Int
tofield(e) =
  @match e begin
    (s_Symbol::t_=_) => :($s::$t)
    (s_Symbol=default_) => :($s::typeof($default))
    (s_Symbol) => :($s::Any)
    (s_Symbol::t_) => e
    _ => error("unknown field pattern $e")
  end

tosymbol(e::Expr) = e.args[1]

tovalue(e) =
  @match e begin
    (_=val_)|(_::_=val_) => val
    (_::Union{Missing,_})|(_::Union{_,Missing}) => missing
  end

"""
Define a basic stable `Base.hash` which just combines the hash of an
instance's `DataType` with the hash of its values
"""
defhash(T, curlies, fields) = begin
  body = foldr((f,e)->:(hash(a.$f, $e)), fields, init=:(hash($T, h)))
  :(Base.hash(a::$T, h::UInt) where {$(curlies...)} = $body)
end

"""
Define a basic `Base.==` which just recurs on each field of the type
"""
defequals(T, curlies, fields) = begin
  isempty(fields) && return nothing # already works
  exprs = map(f->:($isequal(a.$f, b.$f)), fields)
  body = foldr((a,b)->:($a && $b), exprs)
  :(Base.:(==)(a::$T, b::$T) where {$(curlies...)} = $body)
end

export @struct, @mutable
