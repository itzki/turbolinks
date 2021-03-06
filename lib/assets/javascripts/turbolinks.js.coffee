initialized    = false
currentState   = null
referer        = document.location.href
assets         = []
pageCache      = {}
createDocument = null

visit = (url) ->
  if browserSupportsPushState
    cacheCurrentPage()
    reflectNewUrl url
    fetchReplacement url
  else
    document.location.href = url


fetchReplacement = (url) ->
  triggerEvent 'page:fetch'

  xhr = new XMLHttpRequest
  xhr.open 'GET', url, true
  xhr.setRequestHeader 'Accept', 'text/html, application/xhtml+xml, application/xml'
  xhr.setRequestHeader 'X-XHR-Referer', referer

  xhr.onload = =>
    doc = createDocument xhr.responseText

    if assetsChanged doc
      document.location.reload()
    else
      changePage extractTitleAndBody(doc)...
      reflectRedirectedUrl xhr
      resetScrollPosition()
      triggerEvent 'page:load'

  xhr.onabort = -> console.log 'Aborted turbolink fetch!'

  xhr.send()

fetchHistory = (state) ->
  cacheCurrentPage()

  if page = pageCache[state.position]
    changePage page.title, page.body
    recallScrollPosition page
    triggerEvent 'page:restore'
  else
    fetchReplacement document.location.href


cacheCurrentPage = ->
  rememberInitialPage()

  pageCache[currentState.position] =
    url:       document.location.href,
    body:      document.body,
    title:     document.title,
    positionY: window.pageYOffset,
    positionX: window.pageXOffset

  constrainPageCacheTo(10)

constrainPageCacheTo = (limit) ->
  for own key, value of pageCache
    pageCache[key] = null if key <= currentState.position - limit

changePage = (title, body, runScripts) ->
  document.title = title
  document.documentElement.replaceChild body, document.body
  executeScriptTags() if runScripts
  currentState = window.history.state
  triggerEvent 'page:change'

executeScriptTags = ->
  for script in document.body.getElementsByTagName 'script' when script.type in ['', 'text/javascript']
    if script.src? and not script.getAttribute('data-turbolinks-evaluated')?
      copy = document.createElement 'script'
      copy.setAttribute attr.name, attr.value for attr in script.attributes
      copy.setAttribute 'data-turbolinks-evaluated', ''
      parent = script.parentNode
      parent.removeChild script
      parent.insertBefore copy, parent.childNodes[0]
    else
      eval(script.innerHTML)


reflectNewUrl = (url) ->
  if url isnt document.location.href
    referer = document.location.href
    window.history.pushState { turbolinks: true, position: currentState.position + 1 }, '', url

reflectRedirectedUrl = (xhr) ->
  if (location = xhr.getResponseHeader('X-XHR-Current-Location'))
    window.history.replaceState currentState, '', location

rememberCurrentUrl = ->
  window.history.replaceState { turbolinks: true, position: Date.now() }, '', document.location.href

rememberCurrentState = ->
  currentState = window.history.state

rememberCurrentAssets = ->
  assets = extractAssets document

rememberInitialPage = ->
  unless initialized
    rememberCurrentUrl()
    rememberCurrentState()
    createDocument = browserCompatibleDocumentParser()
    initialized = true

recallScrollPosition = (page) ->
  window.scrollTo page.positionX, page.positionY

resetScrollPosition = ->
  window.scrollTo 0, 0


triggerEvent = (name) ->
  event = document.createEvent 'Events'
  event.initEvent name, true, true
  document.dispatchEvent event


extractAssets = (doc) ->
  (node.src || node.href) for node in doc.head.childNodes when node.src or node.href

assetsChanged = (doc)->
  extractedAssets = extractAssets doc
  extractedAssets.length isnt assets.length or intersection(extractedAssets, assets).length != assets.length

intersection = (a, b) ->
  [a, b] = [b, a] if a.length > b.length
  value for value in a when value in b

extractTitleAndBody = (doc) ->
  title = doc.querySelector 'title'
  [ title?.textContent, doc.body, 'runScripts' ]

browserCompatibleDocumentParser = ->
  createDocumentUsingParser = (html) ->
    (new DOMParser).parseFromString html, 'text/html'

  createDocumentUsingWrite = (html) ->
    doc = document.implementation.createHTMLDocument ''
    doc.open 'replace'
    doc.write html
    doc.close()
    doc

  if window.DOMParser
    testDoc = createDocumentUsingParser '<html><body><p>test'

  if testDoc?.body?.childNodes.length is 1
    createDocumentUsingParser
  else
    createDocumentUsingWrite


installClickHandlerLast = (event) ->
  unless event.defaultPrevented
    document.removeEventListener 'click', handleClick
    document.addEventListener 'click', handleClick

handleClick = (event) ->
  unless event.defaultPrevented
    link = extractLink event
    if link?.nodeName is 'A' and !ignoreClick(event, link)
      visit link.href
      event.preventDefault()


extractLink = (event) ->
  link = event.target
  link = link.parentNode until link is document or !link or link.nodeName is 'A'
  link

crossOriginLink = (link) ->
  location.protocol isnt link.protocol or location.host isnt link.host

anchoredLink = (link) ->
  ((link.hash and link.href.replace(link.hash, '')) is location.href.replace(location.hash, '')) or
    (link.href is location.href + '#')

nonHtmlLink = (link) ->
  link.href.match(/\.[a-z]+(\?.*)?$/g) and not link.href.match(/\.html?(\?.*)?$/g)

noTurbolink = (link) ->
  until ignore or link is document
    ignore = link.getAttribute('data-no-turbolink')?
    link = link.parentNode
  ignore

targetLink = (link) ->
  link.target.length isnt 0

nonStandardClick = (event) ->
  event.which > 1 or event.metaKey or event.ctrlKey or event.shiftKey or event.altKey

ignoreClick = (event, link) ->
  crossOriginLink(link) or anchoredLink(link) or nonHtmlLink(link) or noTurbolink(link) or targetLink(link) or nonStandardClick(event)


browserSupportsPushState =
  window.history and window.history.pushState and window.history.replaceState and window.history.state != undefined

if browserSupportsPushState
  rememberCurrentAssets()
  document.addEventListener 'click', installClickHandlerLast, true

  window.addEventListener 'popstate', (event) ->
    fetchHistory event.state if event.state?.turbolinks

# Call Turbolinks.visit(url) from client code
@Turbolinks = { visit }
