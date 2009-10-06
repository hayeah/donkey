class ASS::Client
  def initialize(opts={})
    @rpc_opts = opts
  end
  
  def rpc
    # should lazy start the RPC server
    @rpc ||= ASS.rpc(@rpc_opts)
  end

  def cast(name,method,data,opts={},meta=nil)
    ASS.cast(name,method,data,opts,meta)
  end

  # makes synchronized call through ASS::RPC
  def call(name,method,data,opts={},meta=nil)
    rpc.call(name,method,data,opts,meta)
  end
end
