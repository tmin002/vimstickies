#ifndef VIM_BRIDGE_H
#define VIM_BRIDGE_H

#include <stdbool.h>

typedef void *VSBufferRef;

typedef enum {
    VSModeNormal = 0,
    VSModeInsert = 1,
    VSModeVisual = 2
} VSMode;

typedef struct {
    int line;
    int column;
} VSCursor;

typedef struct {
    int startLine;
    int startColumn;
    int endLine;
    int endColumn;
    bool linewise;
} VSVisualRange;

typedef unsigned char VSChar;

typedef struct {
    int opChar;
    int blockType;
    int numLines;
    VSChar **lines;
} VSYankInfo;

typedef int (*VSClipboardGetCallback)(
    int regname,
    int *numLines,
    VSChar ***lines,
    int *blockType
);
typedef void (*VSYankCallback)(VSYankInfo *yank);

void VSInitialize(void);
VSBufferRef VSCreateBuffer(const char *text);
void VSActivateBuffer(VSBufferRef buffer);

void VSSetText(VSBufferRef buffer, const char *text);
char *VSCopyText(VSBufferRef buffer);
void VSFree(void *pointer);

void VSInput(const char *input);
void VSKey(const char *key);

VSMode VSGetMode(void);
VSCursor VSGetCursor(void);
void VSSetCursor(int line, int column);
bool VSGetVisualRange(VSVisualRange *range);

void VSSetClipboardGetCallback(VSClipboardGetCallback callback);
void VSSetYankCallback(VSYankCallback callback);

#endif
