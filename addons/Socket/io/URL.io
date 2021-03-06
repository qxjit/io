
URL := Notifier clone do(
	cacheFolder := Directory with("/tmp/ioUrlCache/")
	cacheFolder create
	cacheFile := method(MD5; File with(Path with(cacheFolder path, url md5String)))
	cacheOn ::= false
	cacheTimeout := 24*60*60
	followRedirects := true
	
	cacheStore := method(data,
		cacheFile setContents(data)
	)
	
	cacheLoad := method(
		cf := cacheFile
		if(cf exists and(cf lastDataChangeDate secondsSinceNow < cacheTimeout), 
			//writeln("using cache"); 
			setStatusCode(200); cf contents, nil)
	)
	
//metadoc URL category Networking
//metadoc URL copyright Steve Dekorte, 2004
//metadoc URL license BSD revised
/*metadoc URL description The URL object is usefull for fetching web pages and parsing URLs. Example;
<pre>
page := URL clone setURL(\"http://www.google.com/\") fetch
</pre>
*/

	//doc URL url Returns url string.
	url := ""

	/*doc URL setURL(urlString)
	Sets the url string and parses into the protocol, host, port path, and query slots. Returns self.
	*/
	
	socketProto ::= Socket clone
	readHeader ::= nil
	statusCode ::= nil

	init := method(
		self socket := socketProto clone
		self requestHeaders := requestHeaders clone
	)

	setTimeout := method(timeout,
		s := if(getSlot("socket"), socket, socketProto)
		s setReadTimeout(timeout)
		s setWriteTimeout(timeout)
		s setConnectTimeout(timeout)
		self
	)

	setURL := method(s,
		//if(s lastPathComponent pathExtension == "" and s containsSeq("?") == false and s endsWithSeq("/") == false, s = s .. "/")
		url = s asString
		parse
		self
	)

	host ::= nil
	protocol ::= nil

	unparse := method(
		if(host) then(
			d := if(protocol, protocol .. "://", "") .. host .. if(port and port != 80, ":" .. port, "")
		) else(
			d := ""
		)
		self url := d .. path .. if(query, "?" .. query, "")
		url
	)

	/*doc URL escapeString(aString)
	Returns a new String that is aString with the appropriate characters replaced by their URL escape codes.
	*/

	escapeString := method(u,
		u := u clone asMutable
		u replaceSeq("%","%25")
		escapeCodes foreach(k, v, u replaceSeq(k, v))
		u asString
	)

	/*doc URL unescapeString(aString)
	Returns a new String that is aString with the URL escape codes replaced by the appropriate characters.
	*/

	unescapeString := method(u,
		u := u clone asMutable
		escapeCodes foreach(k, v, u replaceSeq(v, k))
		u replaceSeq("%25", "%")
		u asString
	)

	/*doc URL escapeCodes
	Returns a Map whose key/value pairs are special characters and their URL escape codes.
	*/

	escapeCodes := Map clone do(
		atPut(" ","%20")
		atPut("<","%3C")
		atPut(">","%3E")
		atPut("#","%23")
		//atPut("%","%25")
		atPut("{","%7B")
		atPut("}","%7D")
		atPut("|","%7C")
		//atPut("backslash","%5C")
		atPut("^","%5E")
		atPut("~","%7E")
		atPut("[","%5B")
		atPut("]","%5D")
		atPut("\`","%60")
		atPut(";","%3B")
		atPut("/","%2F")
		atPut("?","%3F")
		atPut(":","%3A")
		atPut("@","%40")
		atPut("=","%3D")
		atPut("&","%26")
		atPut("$","%24")
	)

	//doc URL referer Returns the referer String or nil if not set.
	//doc URL setReferer(aString) Sets the referer. Returns self.
	referer ::= nil

	//doc URL clear Private method to clear the URL's parsed attributes.
	clear := method(
		self do(
			protocol := nil
			host  := nil
			port  := 80
			path  := "/"
			query := nil
			error := nil
			request := nil
		)
	)

	//doc URL parse Private method to parse the url.
	parse := method(
		clear

		if(url containsSeq("://")) then(
			names := list("protocol", "host", "path", "query")
			parts := url orderedSplit("://", "/", "?")
			parts foreach(i, v, self setSlot(names at(i), v))
			if(host containsSeq(":"),
				port = host afterSeq(":") asNumber
				host = host beforeSeq(":")
			)
		) else(
			path = url
		)

		if(port == nil, port = 80)
		if(path == nil, path = "/")
		if(protocol and path and path beginsWithSeq("/") not, path = "/" .. path)
		if(protocol == nil, protocol = "http")
		request = if(query, path .. "?" .. query, path)
	)

	//doc URL setRequest(requestString) Private method to set the url request.
	setRequest := method(r,
		request = r
		path = request
		query = if(request, request afterSeq("?"), nil)
	)

	//doc URL with(urlString) Returns a new URL instance for the url in the urlString.
	with := method(s, fromURL,
		u := self clone setURL(s)
		if(fromURL,
			if(u host == nil, u setHost(fromURL host))

			if(u request beginsWithSeq("/") not,
				u setRequest(Path with(fromURL path pathComponent, u path))
			)
		)
		u
	)
	
	fetchWithDelegate := method(delegate,
		result := self fetch
		delegate urlFetched(self, result)
		result
	)

	fetchAndFollowRedirect := method(
		v := self fetch
		if(statusCode == 302 or statusCode == 301,
		 	v = URL with(self headerFields at("Location")) setCacheOn(false) fetch
		)
		v
	)
	
	evFetch := method(
		c := EvConnection clone setAddress(host) setPort(port) connect
		writeln("evFetch ", url)
		r := c newRequest setUri(request) 
		r requestHeaders = self requestHeaders
		r send
		self statusCode := r responseCode
		//writeln("evFetch  got ", r data size, " bytes")
		r data
	)

	//doc URL fetch Fetches the url and returns the result as a Sequence. Returns an Error, if one occurs.
	fetch := method(url, redirected,
		if(url, setURL(url))
		if(protocol == "http", 
			v := fetchHttp
			if(followRedirects and(statusCode == 302 or statusCode == 301),
			 	if(redirected, 
					writeln("DOUBLE REDIRECT on " .. url)
			 		return Error with("Double redirect")
				)
				writeln("REDIRECT TO ", self headerFields at("Location"))
		 		v := self fetch(self headerFields at("Location"), true)
			)
			return v
		)
		Error with("Protocol '" .. protocol .. "' unsupported")
	)

	/*doc URL fetchWithProgress(progressBlock)
	Same as fetch, but with each read, progressBlock is called with the readBuffer 
	and the content size as parameters.
	*/
	fetchWithProgress := method(progressBlock,
		if(protocol == "http", return(fetch(getSlot("progressBlock"))))
		Error with("Protocol '" .. protocol .. "' unsupported")
	)

	/*doc URL stopFetch
	Stops the fetch, if there is one. Returns self.
	*/
	stopFetch := method(socket close; self)

	/*doc URL requestHeader 
	Returns a Sequence containing the request header that will be sent.
	*/
	
	requestHeaders := Map clone
	requestHeaders atPut("User-Agent", "Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/312.8 (KHTML, like Gecko) Safari/312.6)")
	requestHeaders atPut("Connection", "close")
	//requestHeaders atPut("Referer", "")
	requestHeaders atPut("Accept", "*/*")
			
	requestHeader := method(
		header := Sequence clone
		//write("request = [", request, "]\n")
		header appendSeq("GET ", request," HTTP/1.1\r\n")
		header appendSeq("Host: ", host, if(port != 80, ":" .. port, ""), "\r\n")
		if(referer, header appendSeq("Referer: ", referer, "\r\n"))

		requestHeaders foreach(k, v,
			header appendSeq(k, ":", v, "\r\n")
		)
		//header appendSeq("User-Agent: Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/312.8 (KHTML, like Gecko) Safari/312.6\r\n")
		//header appendSeq("User-Agent: curl/7.18.0 (i386-apple-darwin9.2.0) libcurl/7.18.0 zlib/1.2.3\r\n")
		//header appendSeq("Host: ", host, ":", port, "\r\n")
		//header appendSeq("Connection: close\r\n")
		
		//header appendSeq("Accept: */*\r\n")
		//header appendSeq("Accept: text/html\r\n")
		//header appendSeq("Accept: text/html; q=1.0, text/*; q=0.8, image/gif; q=0.6, image/jpeg; q=0.6, image/*; q=0.5, */*; q=0.1\r\n")
		//header appendSeq("Accept: text/*; image/*;\r\n")
		//header appendSeq("Accept-Encoding: gzip, deflate\r\n")
		//header appendSeq("Accept-Language: en\r\n\r\n")
		header appendSeq("\r\n")
		header
	)

	//doc URL headerBreaks Private list of valid header break character sequences.
	headerBreaks := list("\r\r", "\n\n", "\r\n\r\n", "\n\r\n\r")
	
	//doc URL headerBreaks Private list of 2 character valid header break character sequences.
	twoCharheaderBreaks := list("\r\r", "\n\n")
	
	//doc URL headerBreaks Private list of 4 character valid header break character sequences.
	fourCharheaderBreaks := list("\r\n\r\n", "\n\r\n\r")

	//doc URL headerBreaks Private method to connect to the host and write the header.
	connectAndWriteHeader := method(header,
		if(host == nil, return(Error with("No host set")))
		socket returnIfError setHost(host) returnIfError setPort(port) connect returnIfError
		socket appendToWriteBuffer(if(header, header, requestHeader)) write returnIfError
	//	writeln("write [", requestHeader, "]")
	)

	//doc URL fetchRaw Fetch and return the entire response. Note: This may have problems for some request times.
	fetchRaw := method(
		connectAndWriteHeader returnIfError
		socket streamReadWhileOpen returnIfError
		socket readBuffer
	)

	//doc URL setReadHeader(headerString) Private method that parses the headerFields.
	setReadHeader := method(header,
		readHeader = header
		lines := header split("\r\n")
		self headerFields := Map clone
		//lines println
		statusCode = lines first split at(1) asNumber
		lines removeAt(0)
		lines foreach(line,
			headerFields atPut(line beforeSeq(":"), line afterSeq(":") strip)
		)
		self
	)

	//doc URL fetchHttp(optionalProgressBlock) Private method that fetches an http url.
	fetchHttp := method(progressBlock,
		if(cacheOn, r := cacheLoad; if(r, return r))
		connectAndWriteHeader returnIfError
		r := processHttpResponse(progressBlock)
		if(r isError not, cacheStore(r))
		//if(cacheOn and r isError not, cacheStore(r))
		return r
	)
	
	//doc URL processHttpResponse(optionalProgressBlock) Private method that processes http response.
	processHttpResponse := method(progressBlock,
		b := socket readBuffer
		b empty

		// read and separate the header

		//	socket write("\n\n")
		while(socket isOpen,
			socket streamReadNextChunk returnIfError
			match := b findSeqs(headerBreaks)
			if(match,
				setReadHeader(b exclusiveSlice(0, match index))
				b removeSlice(0, match index + match match size - 1)
				break
			)
		)

		if(readHeader == nil, return(Error with("didn't find read header in [" .. b .. "]")))

		contentLength := headerFields at("Content-Length")
		if(contentLength, 
			//writeln("contentLength: ", contentLength)
			contentLength = contentLength asNumber
		)

		while(socket isOpen,
			socket streamReadNextChunk returnIfError
			if(contentLength and b size >= contentLength, break)
			if(getSlot("progressBlock"), progressBlock(b size, contentLength))
		)

		if(headerFields at("Transfer-Encoding") == "chunked",
			//writeln("chunked encoding")
			newB := Sequence clone
			while(index := b findSeq("\r\n"),
				n := b exclusiveSlice(0, index)
				b removeSlice(0, index + 1)
				length := ("0x" .. n) asNumber
				//writeln("length = ", n, " ", length)
				newB appendSeq(b exclusiveSlice(0, length))
				b removeSlice(0, length + 1)
				//writeln("after = [", b exclusiveSlice(0, 10), "]")
			)
			b copy(newB)
		)

		//writeln("b size: ", b size)

		socket close
		if(headerFields at("Content-Encoding") == "gzip", Zlib; b unzip)
		b
	)

	/*doc URL fetchToFile(aFile)
	Fetch the url and save the result to the specified File object. 
	Saving is done as the data is read, which help minimize memory usage. 
	Returns self on success or nil on error.
	*/
	fetchToFile := method(file,
		fetchHttp(block(file write(socket readBuffer); socket readBuffer empty)) returnIfError
		self
	)

	childUrl := method(u,
		if(u beginsWithSeq("http") not,
			if(u beginsWithSeq("/"),
				u = Path with("http://" .. host, u)
			,
				u = Path with(url pathComponent, u)
			)
		)
		URL clone setURL(u) setReferer(url)
	)

	/*doc URL post(parameters, headers)
	Sends an http post message. If parameters is a Map, it's key/value pairs are 
	send as the post parameters. If parameters is a Sequence or String, it is sent directly.
	Any headers in the headers map are sent with the request.
	Returns a sequence containing the response on success or an Error, if one occurs.
	*/
	post := method(parameters, headers,
		parameters ifNil(parameters = "")

		headers ifNil(headers := Map clone)
		headers atIfAbsentPut("User-Agent", "Mozilla/5.0 (Macintosh; U; PPC Mac OS X; en) AppleWebKit/312.8 (KHTML, like Gecko) Safari/312.6")
		hostHeader := if(port != 80, list(host, port) join(":"), host)
		headers atIfAbsentPut("Host", hostHeader)
		headers atIfAbsentPut("Accept", "text/html; q=1.0, text/*; q=0.8, image/gif; q=0.6, image/jpeg; q=0.6, image/*; q=0.5, */*; q=0.1")
		headers atIfAbsentPut("Content-Type", "application/x-www-form-urlencoded")

		header := Sequence clone appendSeq("POST ", request, " HTTP/1.0\r\n")
		headers foreach(name, value,
			header appendSeq(name, ": ", value, "\r\n")
		)

		if(parameters type == "Map") then(
			buffer := Sequence clone
			parameters keys foreach(i, j,
			buffer appendSeq(escapeString(j), "=", escapeString(parameters at(j)))
			if(i < parameters size - 1, buffer appendSeq("&"))
			)
			content := buffer asString
		) else(
			content := parameters
		)

		header appendSeq("Content-Length: ", content size, "\r\n\r\n", content)

		connectAndWriteHeader(header) returnIfError
		processHttpResponse
	)

	//doc URL openOnDesktop Opens the URL in the local default browser. Supports OSX, Windows and (perhaps) other Unixes.
	openOnDesktop := method(
		platform := System platform
		quotedUrl := "\"" .. url .. "\""
		if(platform == "Mac OS/X") then(
			System system("open " .. quotedUrl)
		) elseif(platform containsSeq("Windows")) then(
			result := System shellExecute("open", url)
			result ifError(result := System shellExecute("open", System getEnvironmentVariable("programfiles") .. "\\Internet Explorer\\iexplore.exe", url))
			return(result)
		) else(
			// assume generic Unix?
			System system("open " .. quotedUrl)
		)
	)

	streamDestination ::= nil
	startStreaming := method(
		fetchHttp(block(
			streamDestination write(socket readBuffer) returnIfError
			socket readBuffer empty
		))
	)

	//doc URL test Private test method.
	test := method(
		data := URL with("http://www.yahoo.com/") fetch
	)
	
	domain := method(
		parts := self host split(".") 
		parts removeLast 
		parts last	
	)
)

//doc Object doURL(urlString) Fetches the URL and evals it in the context of the receiver.
Object doURL := method(url, self doString(URL clone setURL(url) fetch))

//doc Sequence asURL Returns a new URL object instance with the receiver as it's url string.
Sequence asURL := method(URL with(self))

