window.addEventListener("DOMContentLoaded", (_) => {
  // Detect if we have ssl
  const protocol = window.location.protocol;
  const wsProtocol = protocol === "https:" ? "wss:" : "ws:";
  let websocket = new WebSocket(
    wsProtocol + "//" + window.location.host + "/websocket"
  );
  let room = document.getElementById("chat-text");

  websocket.addEventListener("message", function (e) {
    let data = JSON.parse(e.data);
    // creating html element
    let p = document.createElement("p");
    p.innerHTML = `<strong>${data.username}</strong>: ${data.text}`;

    room.append(p);
    room.scrollTop = room.scrollHeight; // Auto scroll to the bottom
  });

  let form = document.getElementById("input-form");
  form.addEventListener("submit", function (event) {
    event.preventDefault();
    let username = document.getElementById("input-username");
    let text = document.getElementById("input-text");
    websocket.send(
      JSON.stringify({
        username: username.value,
        text: text.value,
      })
    );
    text.value = "";
  });
});
