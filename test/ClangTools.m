//
//  ClangTools.m
//  test
//
//  Created by Henry on 2021/7/11.
//

#import "ClangTools.h"

// clang依赖库
#include <stdint.h>
#include <stdio.h>
#include <sanitizer/coverage_interface.h>
// dl_info
#import <dlfcn.h>
// 原子队列
#import <libkern/OSAtomic.h>

@implementation ClangTools
//定义原子队列
static OSQueueHead symbolList = OS_ATOMIC_QUEUE_INIT;

//定义符号结构体
typedef struct{
    void *pc;
    void *next;
} SYNode;

// 获取所有符号个数
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop) {
    static uint64_t N;  // Counter for the guards.
    if (start == stop || *start) return;  // Initialize only once.
    printf("INIT: %p %p\n", start, stop);
    for (uint32_t *x = start; x < stop; x++)
      *x = ++N;
}
// 核心方法！！！！
void __sanitizer_cov_trace_pc_guard(uint32_t *guard) {
//    if (!*guard) return; 系统方法哨兵，这里不需要
    //__builtin_return_address(0); 0表示当前函数的栈返回地址,也就是调用该函数的方法地址；
    void *PC = __builtin_return_address(0);
    SYNode *node = malloc(sizeof(SYNode));
    *node = (SYNode){PC,NULL};
    
    //加入队列
    // offsetof两个作用：1. 获取SYNode内存大小 2. 移动SYNode大小后的地址赋值给next
    // offsetof方便链表使用
    OSAtomicEnqueue(&symbolList, node, offsetof(SYNode, next));
}

+(void)clangDataForWriteFile {
    //定义数组
    NSMutableArray<NSString *> * symbolNameList = [NSMutableArray array];
    
    while (YES) {
        // 从队列中取出SYNode
        SYNode * node = OSAtomicDequeue(&symbolList, offsetof(SYNode, next));
        
        if (node == NULL) {
            break;
        }
        
        Dl_info info = {};
        // 根据符号地址获取符号信息
        dladdr(node->pc, &info);
        NSString * tempName = @(info.dli_sname);
        free(node);
        // 除OC方法，其他方法头需要加上_
        BOOL isObjc = [tempName hasPrefix:@"+["]||[tempName hasPrefix:@"-["];
        NSString * symbolName = isObjc ? tempName : [@"_" stringByAppendingString:tempName];
        [symbolNameList addObject:symbolName];
    }
    // 数组取反
    NSEnumerator * enumerator = [symbolNameList reverseObjectEnumerator];
    NSMutableArray * funcs = [NSMutableArray arrayWithCapacity:symbolNameList.count];
    //去重
    NSString * ttempName;
    while (ttempName = [enumerator nextObject]) {
        if (![funcs containsObject:ttempName]) {
            [funcs addObject:ttempName];
        }
    }
    // 当前函数并非属于启动函数
    [funcs removeObject:[NSString stringWithFormat:@"%s",__FUNCTION__]];
    //写文件
    NSString * filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"HRTest.order"];
    NSString * funcStr = [funcs componentsJoinedByString:@"\n"];
    NSData * fileData = [funcStr dataUsingEncoding:NSUTF8StringEncoding];
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:fileData attributes:nil];
    
    NSLog(@"successful-clangTotal : %i",funcs.count);
}
@end
