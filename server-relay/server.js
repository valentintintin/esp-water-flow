const fs = require('fs')
const WebSocketServer = require('websocket').server;
const http = require('http');
const net = require('net');

const data = fs.readFileSync('../app/assets/shower.csv', 'utf8').split('\n');

let client = null;

const server = http.createServer(function(request, response) {
    console.log((new Date()) + ' Received request for ' + request.url);
    response.writeHead(404);
    response.end();
});

server.listen(8080, function() {
    console.log((new Date()) + ' Server is listening on port 8080');
});

wsServer = new WebSocketServer({
    httpServer: server,
    clientTracking: true
});

wsServer.on('request', function(request) {
    const connection = request.accept();
    console.log((new Date()) + ' Connection accepted.');
    
    client = connection;
    
    let dataIndex = 0;
    /*let interval = setInterval(function() {
        if (dataIndex < data.length) {
            const currentData = data[dataIndex++];
            console.log('TX :', currentData);
            connection.sendUTF(currentData);
        } else {
            dataIndex = 0;
        }
    }, 1000);*/    
    
    connection.on('close', function(reasonCode, description) {
        clearInterval(interval);
        interval = null;
        client = null;
        console.log((new Date()) + ' Peer ' + connection.remoteAddress + ' disconnected.');
    });
});


const serverTcp = net.createServer();    

serverTcp.on('connection', handleConnection);
serverTcp.listen(8700, function() {    
  console.log('serverTcp listening to 8700');  
});

function handleConnection(conn) {    
  const remoteAddress = conn.remoteAddress + ':' + conn.remotePort;  
  console.log('new client connection');
  conn.on('data', onConnData);  
  conn.once('close', onConnClose);  
  conn.on('error', onConnError);
  
  function onConnData(d) {  
    console.log('RX :', d.toString('ascii')); 
    if (client) {
        console.log('TX :', d.toString('ascii')); 
        client.sendUTF(d.toString('ascii'));
    }
  }
  
  function onConnClose() {  
    console.log('connection closed', remoteAddress);  
  }
  
  function onConnError(err) {  
    console.log('Connection error: %s', err.message);  
  }  
}
