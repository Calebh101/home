import socket
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
import select
from urllib.parse import urlparse
import requests

import re
import logging

# Set the version
version = "0.0.0A"

# Initialize lists and counters
rewrites = []
rewritten = 0

# Set up logging
logging.basicConfig(filename='/var/www/home/logs/rewrite.log', level=logging.INFO, format='%(asctime)s - %(message)s')

def rewrite_url(urlS):
    global rewritten, rewrites
    rewrites = []  # Reset rewrites for each new call
    rewritten = 0   # Reset rewritten counter for each new call

    url = urlS.split()[0]  # Get the first part of the URL
    uri = url

    # Function to add rewrite action
    def addrewrite(name):
        global rewritten
        rewrites.append(name)
        rewritten += 1

    # Check if URL matches the Google search pattern
    if re.match(r'^(https?://)?(www\.)?google\.com(:[0-9]+)?.*', url):
        if "udm=14" not in url:
            uri = f"{url}&udm=14"
            addrewrite("google.com/search")

    # Build the rewrites string
    rewritesString = ", ".join(rewrites) if rewrites else "none"

    # Set the status based on whether rewrites occurred
    status = "?" if not rewritten else "!"

    # Log the rewrite action
    logging.info(f"[{status}] ({version}) rewrite \"{urlS}\" to \"{uri}\" (rewrites ({len(rewrites)}): {rewritesString})")
    print(f"REWRITE: [{status}] ({version}) rewrite \"{urlS}\" to \"{uri}\" (rewrites ({len(rewrites)}): {rewritesString})")
    
    # Return the rewritten URL
    return uri

def getFull(self, host):
    return f"http://{host}{self.path}"

class ProxyHTTPRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        url = self.path
        full_url = getFull(self, host)
        print(f"GET: {full_url}")
        parsed_url = urlparse(url)
        host = parsed_url.hostname
        port = parsed_url.port if parsed_url.port else 80

        try:
            response = requests.get(url)
            self.send_response(200)
            self.send_header("Content-Type", response.headers.get('Content-Type'))
            self.end_headers()
            self.wfile.write(response.content)
        except requests.exceptions.RequestException as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(f"Error connecting to server: {e}".encode())

    def do_CONNECT(self):
        """Handle HTTPS requests"""
        host, port = self.path.split(':')
        print(f"CONNECT: {host}")
        self.send_response(200, 'Connection Established')
        self.end_headers()

        # Create a tunnel to the target host and port
        client_socket = self.connection
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server_socket:
            server_socket.connect((host, int(port)))
            client_socket.setblocking(0)
            server_socket.setblocking(0)

            # Use select.select() to monitor the sockets for readability
            while True:
                # Use select to wait until the socket is ready for reading/writing
                rlist, wlist, xlist = select.select([client_socket, server_socket], [], [])

                for s in rlist:
                    if s is client_socket:
                        data = client_socket.recv(4096)
                        if data:
                            server_socket.sendall(data)
                        else:
                            return
                    elif s is server_socket:
                        data = server_socket.recv(4096)
                        if data:
                            client_socket.sendall(data)
                        else:
                            return

def start_proxy_server(host='127.0.0.1', port=3128):
    httpd = HTTPServer((host, port), ProxyHTTPRequestHandler)
    print(f"Starting proxy server on {host}:{port}")
    httpd.serve_forever()

if __name__ == "__main__":
    start_proxy_server()
