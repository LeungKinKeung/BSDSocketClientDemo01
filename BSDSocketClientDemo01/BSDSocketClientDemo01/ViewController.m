//
//  ViewController.m
//  BSDSocketClientDemo01
//
//  Created by KinKeung Leung on 2016/11/18.
//  Copyright © 2016年 KinKeung Leung. All rights reserved.
//

#import "ViewController.h"

#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>


@interface ViewController (){
    CFSocketNativeHandle _socketFileDescriptor;
}

// 消息文本框
@property (weak) IBOutlet NSTextField *messageTextField;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // 连接到服务器必要的东西是 确定的服务器IP地址(或可以通过域名获取IP地址)和服务端口
    // 本程序基于IPv4网络下,使用的是TCP/IP协议
    
    // 服务器IPv4的地址(127.0.0.1是本机回送地址，表示服务器在本机上;如百度某服务器的IP地址为202.108.22.5)
    NSString *serverIPv4Address = @"127.0.0.1";
    // 服务器的端口(由服务器程序决定)
    NSInteger serverPort        = 12345;
    
    // 状态
    int status;
    
    /**
        1.创建Socket描述符（你可以联想为一个Socket对象）
        int socket(int addressFamily, int type,int protocol)
        addressFamily:地址协议簇,AF_INET为IPv4,AF_INET6为IPv6
        type:类型,SOCK_STREAM是"流",通常配合IPPROTO_TCP(TCP/IP协议)使用;SOCK_DGRAM为"数据报文",通常配合IPPROTO_UDP(UDP/IP协议)使用
        protocol:传输协议，可以设置为0让系统自动选择合适的协议
     */
    int socketFileDescriptor = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    
    // 等于-1时就代表创建失败
    if (socketFileDescriptor == -1)
    {
        NSLog(@"1.创建Socket描述符失败");
        return;
    }
    
    /************************创建本机套接字地址实例************************/
    
    // 2.创建Socket Address Instance结构体(代表本机)
    struct sockaddr_in localAddressInstance;
    
    // 初始化结构体
    memset(&localAddressInstance, 0, sizeof(localAddressInstance));
    
    // 实例大小(Socket Instance Length)
    localAddressInstance.sin_len            = sizeof(localAddressInstance);
    
    // 协议簇
    localAddressInstance.sin_family         = AF_INET;
    
    // Socket Instance Address.Socket Address (本质是一个32位的unsigned int类型)
    // INADDR_ANY就是指定地址为0.0.0.0的地址，表示这台主机上的任意一个/所有的IP地址
    localAddressInstance.sin_addr.s_addr    = INADDR_ANY;
    
    // 这里不指定端口，让系统自动帮我分配一个49152到65535的端口
    //localAddressInstance.sin_port           = htons(1994);
    
    // 3.绑定，将Socket实例与本机地址以及一个本地端口号绑定
    status = bind(socketFileDescriptor,
                  (const struct sockaddr *)&localAddressInstance,
                  sizeof(localAddressInstance));
    
    // 绑定失败,如果没有指定绑定的端口通常不会发生此错误
    if (status != 0)
    {
        NSLog(@"3.绑定到本机地址和端口失败");
        return;
    }
    
    /************************创建服务器套接字地址实例************************/
    
    // 4.创建sockaddr_in结构体(代表服务器)
    struct sockaddr_in serverAddressInstance;
    
    // 同上
    memset(&serverAddressInstance, 0, sizeof(serverAddressInstance));
    serverAddressInstance.sin_len           = sizeof(serverAddressInstance);
    serverAddressInstance.sin_family        = AF_INET;
    
    // 以下步骤将使用到服务器ip地址和端口
    
    // inet_addr(const char* strptr) 若字符串有效则将字符串转换为32位二进制网络字节序的IPV4地址，否则为INADDR_NONE(网络字节序是啥自己百度)
    in_addr_t instanceAddress               = inet_addr(serverIPv4Address.UTF8String);
    
    if (instanceAddress == INADDR_NONE)
    {
        NSLog(@"4.无效的IP地址字符串");
        return;
    }
    
    // 指定地址
    serverAddressInstance.sin_addr.s_addr   = instanceAddress;
    
    // 指定端口,htons()将整型变量从主机字节顺序转变成网络字节顺序
    serverAddressInstance.sin_port          = htons(serverPort);
    
    
    // 5.连接到服务器，客户端向特定网络地址的服务器发送连接请求，连接成功返回0，失败返回 -1。
    status = connect(socketFileDescriptor,
                     (const struct sockaddr *)&serverAddressInstance,
                     sizeof(serverAddressInstance));
    
    // 连接失败，通常是服务器地址错误，端口不对，端口没有使用，不在同一网络下
    if (status != 0)
    {
        NSLog(@"5.连接到服务器失败");
        return;
    }
    
    // 赋值到成员变量以供在其他方法使用
    _socketFileDescriptor   = socketFileDescriptor;
    
    // 子线程接收数据
    [self performSelectorInBackground:@selector(receiveData)
                           withObject:nil];
}

// 接收消息
- (void)receiveData
{
    // 如果没有断开，就让其一直循环接收
    BOOL isNoDisconnection  = YES;
    
    // 可接收数据的最大长度(等于buffer的大小)
    size_t maximumAcceptableLength   = 32768;
    
    // 创建一个接收数据的缓冲区
    Byte buffer[maximumAcceptableLength];
    
    // 接收到的数据长度
    ssize_t receivedLength           = 0;
    
    // 循环接收数据
    while (isNoDisconnection)
    {
        // 清空缓冲
        memset(&buffer, 0, maximumAcceptableLength);
        
        receivedLength  = 0;
        
        /**
            从 socket 中读取数据，读取成功返回成功读取的字节数(必定少于等于maximumAcceptableLength)，
            否则错误返回 -1 (Socket没有连接等)或 0 (Socket已被服务器断开)，此函数会阻塞当前线程，这就
            是为何要在子线程执行的原因
            int recv(int socketFileDescriptor, char *buffer, int bufferLength, int flags)
            buffer:缓冲区指针
            flags:一般设置为0，忘记是啥来的了
         */
        receivedLength  = recv(_socketFileDescriptor,
                               buffer,
                               maximumAcceptableLength,
                               0);
        
        // 发生错误
        if (receivedLength < 1) {
            if (receivedLength  == -1) NSLog(@"Socket没有连接，或已被本程序断开");
            if (receivedLength  == 0) NSLog(@"Socket已被服务器断开");
            isNoDisconnection   = NO;
            break;
        }
        
        // 这里暂不考虑数据粘包(多包)和断包(少包)问题，以后再介绍
        
        // 提取缓冲区里已接收的二进制数据，转为UTF-8编码的字符串
        NSString *message = [[NSString alloc] initWithBytes:buffer
                                                     length:receivedLength
                                                   encoding:NSUTF8StringEncoding];
        
        NSLog(@"已接收到消息:%@",message);
    };
    
    // 走到这里代表连接断开了，需要关闭Socket
    close(_socketFileDescriptor);
}



// 发送消息
- (IBAction)sendMessageButtonClicked:(NSButton *)sender
{
    // 要发送的消息
    NSString *message           = self.messageTextField.stringValue;
    NSData *messageData         = [message dataUsingEncoding:NSUTF8StringEncoding];
    
    // 发送数据的缓冲区大小
    NSUInteger bufferLength     = 2048;
    
    // 创建一个发送数据的缓冲区
    Byte buffer[bufferLength];
    
    // 要发送的消息的长度
    NSUInteger totalMessageLength   = messageData.length;
    
    // 偏移值，代表已发送的消息长度
    NSUInteger offset               = 0;
    
    while (offset  != totalMessageLength)
    {
        // 准备发送的字节长度
        NSUInteger willSendBytesLength  = totalMessageLength - offset;
        
        if (willSendBytesLength > bufferLength)
        {
            willSendBytesLength = bufferLength;
        }
        
        // 读取赋值到缓冲区
        [messageData getBytes:&buffer
                        range:NSMakeRange(offset, willSendBytesLength)];
        /**
            通过 socket 发送数据，发送成功返回成功发送的字节数，否则返回 -1。
            int send(int socketFileDescriptor, char *buffer, int bufferLength, int flags)
         */
        NSInteger didSendMsgLen = send(_socketFileDescriptor,
                                       buffer,
                                       willSendBytesLength,
                                       0);
        // 假如失败
        if (didSendMsgLen < 1)
        {
            NSLog(@"发送消息失败");
            break;
        }
        
        // 偏移值增加
        offset += didSendMsgLen;
    }
    
    // 偏移值等于总长度时就代表发送完成了，否则就是中途断开了
    if (offset == totalMessageLength)
    {
        NSLog(@"消息发送完成");
    }else
    {
        NSLog(@"连接断开了，需要关闭Socket");
        close(_socketFileDescriptor);
    }
}

/**
 
    客户端无非4个步骤，分别为:
    socket()        创建
    bind()          绑定
    connect()       连接
    recv()/send()   接收/发送
    
    里面必需要确定的参数是 IP地址(如:127.0.0.1)、端口(如:12345)、传输协议(如:TCP/IP)
    connect()/recv()/send() 等接口都是会阻塞线程的，建议放到非UI线程执行尤其recv()
 */




@end
