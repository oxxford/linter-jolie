helpers = require 'atom-linter'
{ BufferedProcess, CompositeDisposable } = require 'atom'

executablePath = atom.config.get( "linter-jolie.jolieExecutablePath" )
pattern = "[^:]+:\\s*(?<file>.+):\\s*(?<line>\\d+):\\s*(?<type>error|warning)\\s*:(?<message>.+)"

module.exports =
	activate: ->
		require( "atom-package-deps" ).install( "linter-jolie" )
		@subscriptions = new CompositeDisposable
		@subscriptions.add(
			atom.config.observe( "linter-jolie.jolieExecutablePath",
				( v ) ->
					executablePath = v.trim()
			)
		)

		#my code starts here

		#lists of all interfaces or ports or types
		inputPorts = {}
		outputPorts = {}
		types = {}
		interfaces = {}

		#function that takes from text every kind of interface or port or type from content of a file
		#fourth paramentr is needed to handle ':' in type declaration
		parse =
			(moduleList, regExp, data, indent) ->
				positionStart = data.indexOf regExp
				currentPosition = data.indexOf '{', positionStart
				currentPosition++
				index = 1
				while index > 0
					openCrl = data.indexOf '{', currentPosition
					closeCrl = data.indexOf '}', currentPosition
					if openCrl == -1
						currentPosition = closeCrl + 1
						index--
						continue
					if openCrl < closeCrl
						currentPosition = openCrl + 1
						index++
					else
						currentPosition = closeCrl + 1
						index--
				positionEnd = currentPosition
				result = data.substring positionStart, positionEnd
				keyStart = data.indexOf ' ', positionStart
				keyStart++
				keyEnd = data.indexOf ' ', keyStart
				key = data.substring keyStart, (keyEnd - indent)
				moduleList[key] = result

		#scaning a directory
		createModuleList =
			(moduleList, regExp, indent)	->
				atom.workspace.scan(new RegExp(regExp),
					( v,e ) ->
						data = (fs.readFileSync v.filePath).toString()
						parse moduleList, regExp, data, indent
				)

		#create lists of a particular interface or port or type
		createModuleList inputPorts, 'inputPort ', 0
		createModuleList outputPorts, 'outputPort ', 0
		createModuleList types, 'type ', 1
		createModuleList interfaces, 'interface ', 0

		subscribe =
			(editor) ->

				#scaning a file. modules from file have bigger priority
				moduleList = {}
				data = editor.getText()
				parse moduleList, 'inputPort ', data, 0
				data = editor.getText()
				parse moduleList, 'outputPort ', data, 0
				data = editor.getText()
				parse moduleList, 'type ', data, 1
				data = editor.getText()
				parse moduleList, 'interface ', data, 0

				#subscription for showing an info
				cursor = editor.getLastCursor()
				@subscriptions.add(
					cursor.onDidChangePosition(
						() ->
							range = cursor.getCurrentWordBufferRange()
							word = editor.getTextInBufferRange range
							getInfo = () ->
								if moduleList[word] != undefined
									info = moduleList[word]
									return info

								if outputPorts[word] != undefined
									info = outputPorts[word]
									return info

								if inputPorts[word] != undefined
									info = inputPorts[word]
									return info

								if types[word] != undefined
									info = types[word]
									return info

								if interfaces[word] != undefined
									info = interfaces[word]
									return info
							infoToShow = getInfo()
							if infoToShow != undefined
								#handle some problems with line translation in html
								infoToShow = infoToShow.split('\n').join '<br />'
								infoToShow = infoToShow.replace '\n', '<br>'
								atom.notifications.addInfo infoToShow
					)
			 )

		#bind a context
		bindSubscribe = subscribe.bind this

		#subscribing added editor
		@subscriptions.add(
			atom.workspace.onDidAddTextEditor(
				(event) ->
					editor = event.textEditor
					filename = editor.getTitle()
					if filename.endsWith(".ol") || filename.endsWith(".iol")
						bindSubscribe editor
			)
		)

		#subscribe existing editors
		editors = atom.workspace.getTextEditors()
		bindSubscribe editor for editor in editors when editor.getTitle().endsWith(".ol") || editor.getTitle().endsWith(".iol")

		#my code ends here
	deactivate: ->
		@subscriptions.dispose()

	provideLinter: =>
		grammarScopes: [ "source.jolie" ]
		scope: "file"
		lintOnFly: true
		lint: ( editor ) ->
			return helpers.exec( executablePath, [ "--check", editor.getPath() ], { stream: "both" } ).then ( data ) ->
				helpers.parse( data.stderr, pattern )
				.map ( issue ) ->
					[ [ lineStart, colStart ], [ lineEnd, colEnd ] ] = issue.range
					issue.range = helpers.rangeFromLineNumber editor, lineStart, colStart
					return issue
