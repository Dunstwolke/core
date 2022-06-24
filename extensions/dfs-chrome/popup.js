let overlay = document.getElementById("overlay");
let overlay_text = document.getElementById("overlay-text");
let input_title = document.getElementById("title");
let input_taglist = document.getElementById("taglist");
let input_saveButton = document.getElementById("saveButton");

function setPageBackgroundColor() {
  chrome.storage.sync.get("color", ({color}) => {
    document.body.style.backgroundColor = color;
  });
}

let global_ws = null;

async function init() {

  let [tab] = await chrome.tabs.query({active : true, currentWindow : true});

  chrome.storage.sync.get("endpoint", ({endpoint}) => {
    var ws = new WebSocket(endpoint, "dfs");

    let is_connected = false

    ws.addEventListener('close', (close) => {
      console.log("websocket-close", close);
      if (is_connected) {
        overlay_text.innerText = "Connection lost!";
      } else {
        overlay_text.innerText = "Service not available!";
      }
      is_connected = false;
      overlay.classList.remove("hidden");
      global_ws = null;
    });
    ws.addEventListener('error', (error) => {
      console.log("websocket-error", error);
    });
    ws.addEventListener('message', (msg) => {
      console.log("websocket-message", msg);
    });
    ws.addEventListener('open', (open) => {
      console.log("websocket-open", open);
      overlay.classList.add("hidden");
      overlay_text.innerText = "Connected!";
      is_connected = true;
      global_ws = ws;
    });
  });

  console.log(tab);

  input_title.value = tab.title;

  input_saveButton.addEventListener("click", async () => {
    if (global_ws != null) {
      let tag_src = input_taglist.value;

      let tags = tag_src.split(' ').map(s => s.trim(",")).filter(x => x != "");

      global_ws.send(JSON.stringify({
        cmd : "store",
        url : tab.url,
        title : input_title.value,
        tags : tags,
      }));
    }

    // chrome.scripting.executeScript({
    //   target : {tabId : tab.id},
    //   function : setPageBackgroundColor,
    // });
  });
}

init();
