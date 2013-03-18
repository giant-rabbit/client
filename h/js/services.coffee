class Hypothesis extends Annotator
  # Events - overridden for good measure. Unused in the angular Annotator.
  events: {}

  # Plugin configuration
  options:
    Heatmap: {}
    Permissions:
      permissions:
        read: ['group:__world__']
      showEditPermissionsCheckbox: false,
      showViewPermissionsCheckbox: false,
      userString: (user) -> user.replace(/^acct:(.+)@(.+)$/, '$1 on $2')
    Threading: {}

  # Internal state
  visible: false      # *  Whether the sidebar is visible

  # Here as a noop just to make the Permissions plugin happy
  # XXX: Change me when Annotator stops assuming things about viewers
  viewer:
    addField: (-> )

  this.$inject = ['$document', '$location', '$rootScope', '$route', 'drafts']
  constructor: ($document, $location, $rootScope, $route, drafts) ->
    super ($document.find 'body')

    # Load plugins
    for own name, opts of @options
      if not @plugins[name] and name of Annotator.Plugin
        this.addPlugin(name, opts)

    # Set up XDM connection
    this._setupXDM()

    # Add user info to new annotations
    this.subscribe 'beforeAnnotationCreated', (annotation) =>
      permissions = @plugins.Permissions
      annotation.user = permissions.options.userId(permissions.user)
      drafts.add annotation

    # Update the heatmap when the host is updated or annotations are loaded
    bridge = @plugins.Bridge
    heatmap = @plugins.Heatmap
    threading = @threading
    for event in ['hostUpdated', 'annotationsLoaded']
      this.subscribe event, =>
        @provider.call
          method: 'getHighlights'
          success: ({highlights, offset}) ->
            heatmap.updateHeatmap
              highlights:
                for hl in highlights when hl.data
                  annotation = bridge.cache[hl.data]
                  angular.extend hl, data: annotation
              offset: offset

  _setupXDM: ->
    $location = @element.injector().get '$location'
    $rootScope = @element.injector().get '$rootScope'
    $window = @element.injector().get '$window'
    drafts = @element.injector().get 'drafts'

    # Set up the bridge plugin, which bridges the main annotation methods
    # between the host page and the panel widget.
    whitelist = ['diffHTML', 'quote', 'ranges', 'target']
    this.addPlugin 'Bridge',
      origin: $location.search().xdm
      window: $window.parent
      formatter: (annotation) =>
        formatted = {}
        for k, v of annotation when k in whitelist
          formatted[k] = v
        formatted
      parser: (annotation) =>
        parsed = {}
        for k, v of annotation when k in whitelist
          parsed[k] = v
        parsed

    @provider = Channel.build
      origin: $location.search().xdm
      scope: 'annotator:panel'
      window: $window.parent
      onReady: =>
        patch_update = (store) =>
          # When the store plugin finishes a request, update the annotation
          # using a monkey-patched update function which updates the threading
          # if the annotation has a newly-assigned id and ensures that the id
          # is enumerable.
          store.updateAnnotation = (annotation, data) =>
            if annotation.id? and annotation.id != data.id
              # Update the id table for the threading
              thread = @threading.getContainer annotation.id
              thread.message.id = data.id
              @threading.idTable[data.id] = thread
              delete @threading.idTable[annotation.id]

              # The id is no longer temporary and should be serialized
              # on future Store requests.
              Object.defineProperty annotation, 'id',
                configurable: true
                enumerable: true
                writable: true

              # If the annotation is loaded in a view, switch the view
              # to reference the new id.
              search = $location.search()
              if search? and search.id == annotation.id
                search.id = data.id
                $location.search(search).replace()

            # Update the annotation with the new data
            annotation = angular.extend annotation, data

            # Give angular a chance to react
            $rootScope.$digest()

            # Update the heatmap
            this.publish 'hostUpdated'

        # Get the location of the annotated document
        @provider.call
          method: 'getHref'
          success: (href) =>
            this.addPlugin 'Store',
              annotationData:
                uri: href
              loadFromSearch:
                limit: 1000
                uri: href
              prefix: '/api/current'
            patch_update this.plugins.Store

        # Dodge toolbars [DISABLE]
        #@provider.getMaxBottom (max) =>
        #  @element.css('margin-top', "#{max}px")
        #  @element.find('#toolbar').css("top", "#{max}px")
        #  @element.find('#gutter').css("margin-top", "#{max}px")
        #  @plugins.Heatmap.BUCKET_THRESHOLD_PAD += max

        this.publish 'hostUpdated'

    @provider

    .bind('publish', (ctx, args...) => this.publish args...)

    .bind('back', =>
      # This guy does stuff when you "back out" of the interface.
      # (Currently triggered by a click on the source page.)
      return unless drafts.discard()
      if $location.path() == '/viewer' and $location.search()?.id?
        $rootScope.$apply => $location.search('id', null).replace()
      else
        this.hide()
    )

  _setupWrapper: ->
    @wrapper = @element.find('#wrapper')
    .on 'mousewheel', (event, delta) ->
      # prevent overscroll from scrolling host frame
      # This is actually a bit tricky. Starting from the event target and
      # working up the DOM tree, find an element which is scrollable
      # and has a scrollHeight larger than its clientHeight.
      # I've obsered that some styles, such as :before content, may increase
      # scrollHeight of non-scrollable elements, and that there a mysterious
      # discrepancy of 1px sometimes occurs that invalidates the equation
      # typically cited for determining when scrolling has reached bottom:
      #   (scrollHeight - scrollTop == clientHeight)
      $current = $(event.target)
      while (
        ($current.css('overflow') in ['visible', '']) or
        ($current[0].scrollHeight == $current[0].clientHeight)
      )
        $current = $current.parent()
        if not $current[0]? then return event.preventDefault()
      scrollTop = $current[0].scrollTop
      scrollEnd = $current[0].scrollHeight - $current[0].clientHeight
      if delta > 0 and scrollTop == 0
        event.preventDefault()
      else if delta < 0 and scrollEnd - scrollTop <= 1
        event.preventDefault()
    this

  _setupDocumentEvents: ->
    el = document.createElementNS 'http://www.w3.org/1999/xhtml', 'canvas'
    el.width = el.height = 1
    @element.append el

    handle = @element.find('#toolbar .tri')[0]
    handle.addEventListener 'dragstart', (event) =>
      event.dataTransfer.setData 'text/plain', ''
      event.dataTransfer.setDragImage el, 0, 0
      @provider.dragFrame event.screenX
    handle.addEventListener 'dragend', (event) =>
      @provider.dragFrame event.screenX
    @element[0].addEventListener 'dragover', (event) =>
      @provider.dragFrame event.screenX
    @element[0].addEventListener 'dragleave', (event) =>
      @provider.dragFrame event.screenX

    this

  # Override things not used in the angular version.
  _setupDynamicStyle: -> this
  _setupViewer: -> this
  _setupEditor: -> this

  # (Optionally) put some HTML formatting around a quote
  getHtmlQuote: (quote) -> quote

  setupAnnotation: (annotation) ->
    # Delagate to Annotator implementation after we give it a valid array of
    # targets. This is needed until Annotator stops assuming targets need to be
    unless annotation.target?
      annotation.highlights = []
      annotation.target = []
    @plugins.Threading.thread annotation
    annotation

  showViewer: (annotations=[]) =>
    @element.injector().invoke [
      '$location', '$rootScope',
      ($location, $rootScope) ->
        $rootScope.annotations = annotations
        $location.path('/viewer').replace()
        $rootScope.$digest()
    ]
    this.show()
    this

  showEditor: (annotation) =>
    @element.injector().invoke [
      '$location', '$rootScope', '$route'
      ($location, $rootScope, $route) ->
        # Set the path
        $location.path('/editor').search('id', null).replace()

        # Digest the change
        $rootScope.$digest()

        # Push the annotation into the editor scope
        if $route.current.controller is 'EditorController'
          $route.current.locals.$scope.$apply (s) -> s.annotation = annotation
    ]
    this.show()
    this

  show: =>
    @visible = true
    @provider.notify method: 'showFrame'
    @element.find('#toolbar').addClass('shown')
      .find('.tri').attr('draggable', true)

  hide: =>
    @lastWidth = window.innerWidth
    @visible = false
    @provider.notify method: 'setActiveHighlights'
    @provider.notify method: 'hideFrame'
    @element.find('#toolbar').removeClass('shown')
      .find('.tri').attr('draggable', false)


class DraftProvider
  drafts: []

  $get: -> this
  add: (draft) -> @drafts.push draft unless this.contains draft
  remove: (draft) -> @drafts = (d for d in @drafts when d isnt draft)
  contains: (draft) -> (@drafts.indexOf draft) != -1

  discard: ->
    count = (d for d in @drafts when d.text?.length).length
    text =
      switch count
        when 0 then null
        when 1
          """You have an unsaved reply.

          Do you really want to discard this draft?"""
        else
          """You have #{count} unsaved replies.

          Do you really want to discard these drafts?"""

    if count == 0 or confirm text
      @drafts = []
      true
    else
      false


class FlashProvider
  queues:
    info: []
    error: []
    success: []
  notice: null
  timeout: null

  constructor: ->
    # Configure notification classes
    angular.extend Annotator.Notification,
      INFO: 'info'
      ERROR: 'error'
      SUCCESS: 'success'

  _process: ->
    @timeout = null
    for q, msgs of @queues
      if msgs.length
        notice = Annotator.showNotification msgs.shift(), q
        @timeout = this._wait =>
          # work around Annotator.Notification not removing classes
          for _, klass of notice.options.classes
            notice.element.removeClass klass
          this._process()
        break

  $get: ['$timeout', 'annotator', ($timeout, annotator) ->
    this._wait = (cb) -> $timeout cb, 5000
    angular.bind this, this._flash
  ]

  _flash: (queue, messages) ->
    if @queues[queue]?
      @queues[queue] = @queues[queue]?.concat messages
      this._process() unless @timeout?


angular.module('h.services', [])
  .provider('drafts', DraftProvider)
  .provider('flash', FlashProvider)
  .service('annotator', Hypothesis)
