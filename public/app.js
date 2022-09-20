function colorfrom(username) {
  let hash = 0;
  for (let i = 0; i < username.length; i++) {
    hash = username.charCodeAt(i) + ((hash << 5) - hash);
  }
  let color = "#";
  for (let i = 0; i < 3; i++) {
    let value = (hash >> (i * 8)) & 0xff;
    color += ("00" + value.toString(16)).substr(-2);
  }
  return color;
}

function main() {
  // Detect if we have ssl
  const protocol = window.location.protocol;
  const wsProtocol = protocol === "https:" ? "wss:" : "ws:";
  let websocket = new WebSocket(
    wsProtocol + "//" + window.location.host + "/websocket"
  );
  let room = document.getElementById("chat-text");
  room.innerHTML = "";

  websocket.addEventListener("message", function (e) {
    let data = JSON.parse(e.data);
    // creating html element
    let p = document.createElement("tr");
    p.innerHTML = `<td>${data.time}<td><td style="color: ${colorfrom(
      data.username
    )}"><strong>${data.username}:</strong><td><td>${data.text}<td>`;

    room.prepend(p);
    room.scrollTop = room.scrollHeight; // Auto scroll to the bottom
  });

  let sendfunc = function (event) {
    event.preventDefault();
    let username = document.getElementById("input-username");
    let text = document.getElementById("input-text");
    websocket.send(
      JSON.stringify({
        username: username.value,
        text: text.value,
        time: new Date().toLocaleTimeString(),
      })
    );
    text.value = "";
  };

  let form = document.getElementById("input-form");
  form.addEventListener("submit", sendfunc);
  websocket.addEventListener("close", function (e) {
    console.log("Connection closed, reconnecting...");
    form.removeEventListener("submit", sendfunc);
    setTimeout(function () {
      websocket = main();
    }, 1000);
  });
}

window.addEventListener("DOMContentLoaded", (_) => {
  main();
});
