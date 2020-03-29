LibWebKit.gtk_init(nil, nil)

# A `WebView` is a class which represents a WebKit2GTK browser window.
# It allows developers to display HTML contents, execute JavaScript code.
class WebView
  @script_finish_callback = Pointer(Void).null
  @document_loaded_callback = Pointer(Void).null
  @extension_dir : String = ""

  alias Callback = WebView -> Void

  # Get extension directory
  getter extension_dir

  # Initializes a new instance of `WebView`
  def initialize
    @window = LibWebKit.new_window LibWebKit::GTKWindowType::TOP_LEVEL
    @scroll_panel = LibWebKit.new_scrollable_container nil, nil
    @browser = LibWebKit.create_web_view
    @settings = LibWebKit.get_webview_settings @browser
    LibWebKit.add_view_to_parent @window, @scroll_panel
    LibWebKit.add_view_to_parent @scroll_panel, @browser
  end

  # Specifies *directory* where the webview should look for WebExtension.
  #
  # ```
  # webview = WebView.new
  # webview.extension_dir = "<your-path-to-directory-which-contains-web-extensions>"
  # ```
  # NOTE: If this method is used, it should be executed as soon as possible. A good practice is to place it right after `.new`.
  def extension_dir=(directory : String)
    @extension_dir = path
    LibWebKit.connect_signal LibWebKit.get_default_web_context, "initialize-web-extensions", (->(ctx : Void*, data : Void*, c : Void*) {
      default_ctx = LibWebKit.get_default_web_context
      LibWebKit.set_extensions_directory default_ctx, ctx.as(UInt8*)
    }), @extension_dir.to_unsafe, nil, LibWebKit::GtkGConnectFlags::All
  end

  # Set default size of browser window
  #
  # ```
  # webview.default_size 800, 600
  # ```
  def default_size(width : UInt32, height : UInt32)
    LibWebKit.set_default_window_size @window, width, height
  end

  # Set title of browser window
  #
  # ```
  # webview.title = "Alizarin App"
  # ```
  def title=(title : String)
    LibWebKit.set_title(@window, title)
  end

  # Set properties for WebKitSettings. See [WebKitSettings](https://webkitgtk.org/reference/webkit2gtk/stable/WebKitSettings.html).
  #
  # ```
  # webview["enable-developer-extras"] = true    # This allows developers to use WebInspector(DevTools)
  # webview["enable-html5-local-storage"] = true # This enables localStorage features in JavaScript
  # ```
  def []=(name : String, value)
    LibWebKit.g_object_set @settings, name, value, nil
  end

  # Loads a webpage located at *url*
  #
  # ```
  # webview.load_url "https://google.com"
  # ```
  def load_url(url : String)
    LibWebKit.webview_load_uri @browser, url
  end

  # Specifies callback called when browser window close. Usually useds to close process.
  #
  # ```
  # webview.on_close do |webview|
  #   puts "WebView(#{webview}) is going to shutdown"
  #   exit 0
  # end
  # ```
  def on_close(&b : Callback)
    @box = Box.box({self, b})
    LibWebKit.connect_signal @browser, "destroy", ->(data1 : Void*, data2 : Void*, data3 : Void*) {
      data = Box({WebView, Callback}).unbox(data1)
      webview = data[0]
      callback = data[1]
      webview.destroy_browser
      callback.call webview
    }, @box, nil, LibWebKit::GtkGConnectFlags::All
  end

  # Shows WebKit's WebInspector.
  def show_inspector
    inspector = LibWebKit.get_web_inspector @browser
    LibWebKit.show_inspector inspector
  end

  # Runs browser window. This method puts the main process into a loop which blocks until callback specified in `#on_close` called.
  #
  # ```
  # webview.run
  # puts "Good bye" # This line will only be executed after webview main loop is destroyed.
  # ```
  def run
    LibWebKit.show_window @window
    LibWebKit.start_gtk_main_loop
  end

  # Run browser window. This method receives a *block* which lets developers do some logics at each webview's iteration.
  # If *blocking* is truthy, *block* will only be called when an iteration is done.
  #
  # ```
  # count = 0
  # webview.run blocking: false do |webview|
  # #If blocking: set to `true`. This printing process will be significally slowed down.
  # #This is because `#run(blocking,&block)` has to wait for the current iteration finish.
  #   puts a
  #   a += 1
  # end
  # ```
  def run(blocking : Bool, &block : WebView -> Nil)
    LibWebKit.show_window @window
    while LibWebKit.start_gtk_main_iter(blocking)
      b.call self
    end
  end

  # Asynchronously executes JavaScriptCode. After *js_code* has been successfully executed, the callback passed to `#when_script_finished` will be called.
  #
  # ```
  # webview.when_document_loaded |w|
  #   w.execute_javascript "alert('LOL')"
  # end
  # ```
  def execute_javascript(js_code : String)
    LibWebKit.eval_js @browser, js, nil,
      LibWebKit::GAsyncReadyCallback.new { |object, result, user_data|
        res = LibWebKit.script_finish_result object, result, nil
        if res.null?
          puts "JavaScript execution has cause error(s)".colorize(:red).on(:black)
          return
        end
        jsc_value = LibWebKit.get_jsc_from_js_result res
        webview = Box(WebView).unbox(user_data)
        webview.run_script_finish_callback jsc_value
      }, Box.box(self)
  end

  # Specifies a callback which will be called each time a script executed by `#execute_javascript` finishes.
  # The callback *b* receives a `Pointer(Void)` as parameter that points to result of the executed JS code.
  # For example:
  #
  # ```
  # webview.when_script_finished do |js_value|
  #   puts JSC.is_number jsc_value
  # end
  # webview.execute_javascript "1 + 2"          # => js_value in the block above should be true
  # webview.execute_javascript "alert('Hello')" # => js_value should be false
  # ```
  # NOTE: Because the passed block receives a Pointer as its parameter, it's considered unsafe. It's not recommended to manipulate this pointer directly
  # using JavaScriptCore API. Uses `WebExtension` instead.
  def when_script_finished(&b : JSC::JSValue -> Nil)
    @script_finish_callback = Box.box(b)
  end

  # Specifies a callback which will be called after webview has fully loaded a webpage.
  # This is equal to JQuery's `$(window).ready`.
  # This method is the right place to do some logic, for example `#execute_javascript`.
  #
  # ```
  # webview.on_document_loaded do |webview|
  #   webview.execute_javascript "alert('Hello')"
  # end
  # ```
  def when_document_loaded(&b : WebView -> Nil)
    @document_loaded_callback = Box.box({self, b})
    LibWebKit.connect_signal @browser, "load-changed",
      LibWebKit::GtkCallback.new { |udata, event, webview|
        if event.address == 3
          data = Box({WebView, (WebView -> Nil)}).unbox udata
          webview = data[0]
          callback = data[1]
          callback.call webview
        end
      }, @document_loaded_callback, nil, LibWebKit::GtkGConnectFlags::All
  end

  protected def run_script_finish_callback(js_value : JSC::JSValue)
    unless @script_finish_callback.null?
      callback = Box(JSC::JSValue -> Nil).unbox @script_finish_callback
      callback.call js_value
    end
  end

  protected def destroy_browser
    LibWebKit.destroy_widget @browser
  end
end
