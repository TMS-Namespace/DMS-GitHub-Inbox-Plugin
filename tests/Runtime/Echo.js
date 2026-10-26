// Echo.js - minimal worker with no plugin code, used to detect host-runtime startup diagnostics.
WorkerScript.onMessage = function (message) {
    WorkerScript.sendMessage(message);
};
