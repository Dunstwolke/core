# DunstFabric

All connected Dunstwolke devices will form a common fabric which allows IPC calls between different applications, even if those run on different devices.

Each device runs a central fabric daemon that will perform discovery of known devices and will do all dispatching of system calls. The fabric daemon is also able to spawn applications.

Applications are written in [Wasm](https://webassembly.org/) or in a native language. Wasm applications can be transferred seamlessly between devices, while native applications are tied to the host machine.

## Application Design

Applications have a entry point that will set up the application, but in contrast to other operating systems, the entry point will return to the OS. Now when events happen, the applications will be called with a set of events that lead to the wakeup of the application. The purpose of the entry point is only initialization and request of events.

## Syscall Design

The following sections describe the rough ideas of a system call design for the Dunstwolke Fabric.

### Fabric Management

- `listKnownDevices() []Device` lists all devices in the current fabric
- `listAvailableDevices() []Device` lists all devices that are available at the moment
- `removeDevice(Device) void` removes a device from the fabric
- `addDevice() Device` pairs a new device to the fabric

### Process Management

- `listProcesses() []{ Pid, Device }` lists all running processes
- `listProcesses(Device) []Pid` lists all running processes for a device
- `getProcessStats(Pid) ?struct { … }` returns the statistics for a process if any
- `kill(Pid) void` kills a given process
- `spawn(File, []String) Pid` spawns a new process with the given args and file
- `moveProcess(Pid, Device) void` moves a process to a new device

### IPC

The IPC of the fabric will work from applications to other applications targeting a certain subsystem identified by a Guid.

- `createIpcService(Guid, display_name) ServiceHandle` will make this application provide a new IPC subsystem
- `destroyIpcService(ServiceHandle) void` will shut down a previously established IPC subsystem
- `getIpcMessage(ServiceHandle, blocking, *Pid, *[]u8) bool` will receive a IPC message
- `sendIpcMessage(Guid, ?Pid, []u8)` will send a message to the service `Guid` with an optional target application

> TODO: How to manage IPC responses? A non-Service might want to have answer to things

### Network

Network system calls operate on the ip address of the fabric. Each fabric will have a one or more outbound ip address which are routed via a single device. An application creating the socket for an ip does not have to run on the same device that has this ip.

- `createUdpSock(ip, port) UdpSocketHandle` creates a new udp socket bound to the given port
- `closeUdpSock(UdpSocketHandle) void` destroys a previously created socket
- `sendTo(UdpSocketHandle, ip, port, []u8) usize` sends data to a udp address
- `receiveFrom(UdpSocketHandle, *ip, *port, *[]u8) usize` reads data from the udp port
- `getSocketName(UdpSocketHandle, *ip, *port) void`
