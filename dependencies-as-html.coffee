path = require('path')

# For a given dependency tree, returns the <script> or <link> tags necessary
# to include the the whole dependency tree into a HTML document. Also inserts
# HTML comments to make following the tree easier.
#
# You can pass in a `dependencyType` into the options paramater to only include
# a specific type of dependnecy (likely needed if you have more than one
# dependency type).
#
# For example:
#
#    <!-- From ParagonUI/static/bundles/project.css (total files: 10) -->
#    <!-- From ParagonUI/static/sass/app.css  -->
#    <!-- From shepherd/static-2.56/css/shepherd.css  -->
#    <link href="/shepherd-os/static-1.5/css/shepherd-theme-arrows-plain-buttons.css" rel="stylesheet" type="text/css" />
#    <link href="/shepherd/static-2.56/css/shepherd.css" rel="stylesheet" type="text/css" />
#    <!-- End shepherd/static-2.56/css/shepherd.css -->
#    <link href="/odometer/static-1.7/themes/odometer-theme-minimal.css" rel="stylesheet" type="text/css" />
#    <!-- From vex/static-2.8/css/vex.css  -->
#    <link href="/vex-os/static-1.6/css/vex.css" rel="stylesheet" type="text/css" />
#    <link href="/vex/static-2.8/css/vex.css" rel="stylesheet" type="text/css" />
#    <!-- End vex/static-2.8/css/vex.css -->
#    <link href="/style_guide/static/sass/contrib/sticky-footer.css" rel="stylesheet" type="text/css" />
#    <link href="/ParagonUI/static/sass/app.css" rel="stylesheet" type="text/css" />
#    <!-- End ParagonUI/static/sass/app.css -->
#    <link href="/ParagonUI/static/sass/browsers.css" rel="stylesheet" type="text/css" />
#    <link href="/ParagonUI/static/sass/unicorns.css" rel="stylesheet" type="text/css" />
#    <link href="/ParagonUI/static/bundles/project.css" rel="stylesheet" type="text/css" />
#    <!-- End ParagonUI/static/bundles/project.css -->
#
# And:
#
#     <!-- From style_guide/static/js/style_guide_plus_layout_head.js (total files: 20) -->
#     <!-- From style_guide/static/js/head/index.js  -->
#     <script src="/style_guide/static/js/head/browser-os-css-classes.js" type="text/javascript"></script>
#     <!-- From style_guide/static/js/head/core.js  -->
#     <!-- From common_assets/static-2.110/js/core/index.js  -->
#     <script src="/common_assets/static-2.110/js/core/console-shim.js" type="text/javascript"></script>
#     <script src="/common_assets/static-2.110/js/core/hns.js" type="text/javascript"></script>
#     <script src="/common_assets/static-2.110/js/core/hubspot.require.js" type="text/javascript"></script>
#     <script src="/common_assets/static-2.110/js/core/future-jquery.js" type="text/javascript"></script>
#     <script src="/common_assets/static-2.110/js/core/htmlEscape.js" type="text/javascript"></script>
#     <script src="/common_assets/static-2.110/js/core/isElement.js" type="text/javascript"></script>
#     <script src ="/common_assets/static-2.110/js/core/index.js" type="text/javascript"></script>
#     <!-- End common_assets/static-2.110/js/core/index.js -->
#     <script src="/style_guide/static/js/head/core.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/head/core.js -->
#     <!-- From style_guide/static/js/head/enviro.js  -->
#     <script src="/enviro/static-3.39/coffee/env.js" type="text/javascript"></script>
#     <script src="/style_guide/static/js/head/enviro.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/head/enviro.js -->
#     <script src="/style_guide/static/js/head/index.js" type="text/javascript"></script>
#     <!-- From style_guide/static/js/head/modernizr-2.6.0-custom.js  -->
#     <script src="/common_assets/static-2.110/js/modernizr/modernizr-2.6.0-custom.js" type="text/javascript"></script>
#     <script src="/style_guide/static/js/head/modernizr-2.6.0-custom.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/head/modernizr-2.6.0-custom.js -->
#     <!-- From style_guide/static/js/head/portal-id-parser.js  -->
#     <script src="/PortalIdParser/static-1.12/coffee/parser.js" type="text/javascript"></script>
#     <script src="/style_guide/static/js/head/portal-id-parser.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/head/portal-id-parser.js -->
#     <script src="/style_guide/static/js/head/raven-options.js" type="text/javascript"></script>
#     <script src="/style_guide/static/js/head/raven.js" type="text/javascript"></script>
#     <script src="/style_guide/static/js/head/index.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/head/index.js -->
#     <script src="/style_guide/static/js/style_guide_plus_layout_head.js" type="text/javascript"></script>
#     <!-- End style_guide/static/js/style_guide_plus_layout_head.js -->

dependenciesAsHTML = (tree, options = {}) ->
  formatValue = options.formatValue ? (v) -> v
  filterFunc = options.filter

  if not options.expandedDebugMode
    htmlToIncludeDep(this, tree.relativePath)
  else
    dependenciesHTMLContent = []

    tree.traverseByType options.dependencyType, (node, visitChildren, depth) ->
      if not filterFunc? or filterFunc(node) is true
        val = formatValue(node.relativePath)
        numSprocketsDeps = node.childrenForType(options.dependencyType).length

        dependenciesHTMLContent.push preIncludeComment(node, options.dependencyType, val, depth) if numSprocketsDeps > 0

        visitChildren()

        dependenciesHTMLContent.push htmlToIncludeDep(node, options.dependencyType, val)
        dependenciesHTMLContent.push postIncludeComment(node, options.dependencyType, val) if numSprocketsDeps > 0
      else
        console.log "Filtering out #{node.relativePath} from the expanded HTML output"

    dependenciesHTMLContent.join('\n').replace(/\n\n\n/g, '\n\n').replace(/^\n/, '')

preIncludeComment = (node, dependencyType, formattedValue, depth) ->
  extra = ''
  extra = "(total files: #{node.sizeForType(dependencyType)})" if depth is 0

  "\n<!-- From #{formattedValue} #{extra} -->"

postIncludeComment = (node, dependencyType, formattedValue) ->
  "<!-- End #{formattedValue} -->\n"

htmlToIncludeDep = (node, dependencyType, formattedValue) ->
  val = formattedValue
  val = "/#{val}" unless val[0] is '/'

  ext = path.extname(val).slice(1)

  if ext is 'js'
    """<script src="#{val}" type="text/javascript"></script>"""
  else if ext is 'css'
    """<link href="#{val}" rel="stylesheet" type="text/css" />"""
  else
    throw new Error "Can't create HTML element for unknown file type: #{formattedValue}"


module.exports = dependenciesAsHTML
