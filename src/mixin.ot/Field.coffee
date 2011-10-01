text = require 'share/lib/types/text'

Field = module.exports = (model, @path, @version = 0, @type = text) ->
  # @type.apply(snapshot, op)
  # @type.transform(op1, op2, side)
  # @type.normalize(op)
  # @type.create() -> ''

  @model = model
  @snapshot = null
  @queue = []
  @pendingOp = null
  @pendingCallbacks = []
  @inflightOp = null
  @inflightCallbacks = []
  @serverOps = {}

  self = this
  model._on 'change', (op, oldSnapshot, isRemote) ->
    for {p, i, d} in op
      if i
        model.emit 'insertOT', [self.path, i, p], !isRemote
      else
        model.emit 'delOT', [self.path, d, p], !isRemote
    return

  # Decorate model prototype
  model.insertOT = (path, str, pos, callback) ->
    # TODO Still need to normalize path
    field = @otFields[path] ||= new OT @, path
    pos ?= 0
    op = [ { p: pos, i: str } ]
    op.callback = callback if callback
    field.submitOp op

  # Decorate adapter

  return

Field:: =
  onRemoteOp: (op, v) ->
    # TODO
    return if v < @version
    throw new Error "Expected version #{@version} but got #{v}" unless v == @version
    docOp = @serverOps[@version] = op
    if @inflightOp
      [@inflightOp, docOp] = xf @inflightOp, docOp
    if @pendingOp
      [@pendingOp, docOp] = xf @pendingOp, docOp

    @version++
    @otApply docOp, true

  otApply: (docOp, isRemote) ->
    oldSnapshot = @snapshot
    @snapshot = @type.apply oldSnapshot, docOp
    @model.emit 'change', docOp, oldSnapshot, isRemote
    return @snapshot

  submitOp: (op, callback) ->
    type = @type
    op = type.normalize op
    @otApply op
    @pendingOp = if @pendingOp then type.compose @pendingOp, op else op
    @pendingCallbacks.push callback if callback
    setTimeout @flush, 0

  # Sends ops to the server
  flush: ->
    # Only one inflight op at a time
    return if @inflightOp != null || @pendingOp == null

    @inflightOp = @pendingOp
    @pendingOp = null
    @inflightCallbacks = @pendingCallbacks
    @pendingCallbacks = []

    # @model.socket.send msg, (err, res) ->
    @model.socket.emit 'otOp', path: @path, op: @inflightOp, v: @version, (err, {ver}) =>
      # TODO console.log arguments
      oldInflightOp = inflightOp
      inflightOp = null
      if err
        unless @type.invert
          throw new Error "Op apply failed (#{err}) and the OT type does not define an invert function."

        undo = @type.invert oldInflightOp
        if pendingOp
          [pendingOp, undo] = @xf pendingOp, undo
        otApply undo, true
        callback err for callback in @inflightCallbacks
        return @flush

      unless ver == @version
        throw new Error 'Invalid version from server'

      @serverOps[@version] = oldInflightOp
      @version++
      callback null, oldInflightOp for callback in @inflightCallbacks
      @flush()

  xf: (client, server) ->
    client_ = @type.transform client, server, 'left'
    server_ = @type.transform server, client, 'right'
    return [client_, server_]