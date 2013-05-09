racer = require 'racer'
templates = require './templates.coffee'

racer.ready (model) -> $ ->
  window.model = model

  list = $('#todos')
  listModel = model.at '_page.todoList'

  ## Update the DOM when the model changes ##

  listModel.on 'change', '*.completed', (index, value) ->
    item = list.children().eq(index)
    item.toggleClass 'completed', value
    item.find('[type=checkbox]').prop 'checked', value

  listModel.on 'change', '*.text', (index, value) ->
    item = list.children().eq(index).find('.text')
    return if item.is ':focus'
    item.html value

  listModel.on 'insert', (index, values) ->
    html = (templates.todo value for value in values).join ''
    target = list.children().eq(index)
    if target.length
      target.before html
    else
      list.append html

  listModel.on 'remove', (index, removed) ->
    list.children().slice(index, index + removed.length).remove()

  listModel.on 'move', (from, to, howMany, isLocal, pass) ->
    # If caused by sortable, it will have already moved the element
    return if pass == 'sortable'
    moved = list.children().slice from, from + howMany
    index = if from > to then to else to + howMany
    target = list.children().eq index
    if target.length
      target.before moved
    else
      list.append moved

  ## Update the model in response to DOM events ##

  $('#head').on 'submit', ->
    # Don't add a blank todo
    return unless text = htmlEscape $('#new-todo').val()
    $('#new-todo').val ''
    # Insert the new todo before the first completed item
    items = listModel.get()
    for todo, i in items
      break if todo.completed
    listModel.insert i,
      id: model.id()
      completed: false
      text: text

  list.on 'change', '[type=checkbox]', (e) ->
    item = $(e.target).parents('li')
    index = list.children().index(item)
    listModel.set index + '.completed', e.target.checked
    # Move the item to the bottom if it was checked off
    listModel.move index, -1 if e.target.checked

  list.on 'click', '.delete', (e) ->
    item = $(e.target).parents('li')
    index = list.children().index(item)
    listModel.remove index

  from = null
  list.sortable
    handle: '.handle'
    axis: 'y'
    containment: '#dragbox'
    start: (e, ui) ->
      item = ui.item[0]
      from = list.children().index(item)
    update: (e, ui) ->
      item = ui.item[0]
      to = list.children().index(item)
      # model.pass() will pass an extra argument along to events resulting from
      # mutations. It is often used to ignore events when something has already
      # been updated and to avoid infinite loops
      listModel.pass('sortable').move from, to

  # Watch for changes to the contenteditable fields
  lastHtml = ''
  checkChanged = (e) ->
    html = $('#content').html()
    return if html == lastHtml
    lastHtml = html
    item = $(e.target).parents('li')
    index = list.children().index(item)
    listModel.set index + '.text', e.target.innerHTML
  # Paste and dragover events are fired before the HTML is actually updated
  checkChangedDelayed = (e) ->
    setTimeout checkChanged, 10, e

  # Shortcuts
  # Bold: Ctrl/Cmd + B
  # Italic: Ctrl/Cmd + I
  # Clear formatting: Ctrl/Cmd + Space -or- Ctrl/Cmd + \
  checkShortcuts = (e) ->
    return unless e.metaKey || e.ctrlKey
    code = e.which
    return unless command = (switch code
      when 66 then 'bold'
      when 73 then 'italic'
      when 32 then 'removeFormat'
      when 220 then 'removeFormat'
      else null
    )
    document.execCommand command, false, null
    e.preventDefault() if e.preventDefault
    return false

  $('#content')
    .keydown(checkShortcuts)
    .keydown(checkChanged)
    .keyup(checkChanged)
    .bind('paste', checkChangedDelayed)
    .bind('dragover', checkChangedDelayed)

  # Tell Firefox to use elements for styles instead of CSS
  # See: https://developer.mozilla.org/en/Rich-Text_Editing_in_Mozilla
  document.execCommand 'useCSS', false, true
  document.execCommand 'styleWithCSS', false, false

  htmlEscape = (s) ->
    unless s? then '' else s.toString().replace /&(?!\s)|</g, (s) ->
      if s is '&' then '&amp;' else '&lt;'
