#include "VimBridge.h"

#include <stdlib.h>
#include <string.h>

typedef unsigned char char_u;
typedef long linenr_T;
typedef int colnr_T;
typedef struct file_buffer buf_T;
typedef struct {
    linenr_T lnum;
    colnr_T col;
    colnr_T coladd;
} pos_T;

extern void vimInit(int argc, char **argv);
extern buf_T *vimBufferNew(int flags);
extern void vimBufferSetCurrent(buf_T *buffer);
extern void vimBufferSetLines(
    buf_T *buffer,
    linenr_T start,
    linenr_T end,
    char_u **lines,
    int count
);
extern char_u *vimBufferGetLine(buf_T *buffer, linenr_T line);
extern size_t vimBufferGetLineCount(buf_T *buffer);
extern void vimInput(char_u *input);
extern void vimKey(char_u *key);
extern int vimGetMode(void);
extern pos_T vimCursorGetPosition(void);
extern void vimCursorSetPosition(pos_T position);
extern int vimVisualIsActive(void);
extern int vimVisualGetType(void);
extern void vimVisualGetRange(pos_T *start, pos_T *end);
extern void vimWindowSetWidth(int width);
extern void vimWindowSetHeight(int height);
extern void vimSetClipboardGetCallback(
    int (*callback)(int, int *, char_u ***, int *)
);
extern void vimSetYankCallback(void (*callback)(void *yankInfo));

enum {
    VimModeNormal = 0x01,
    VimModeVisual = 0x02,
    VimModeInsert = 0x10
};

typedef struct {
    int op_char;
    int extra_op_char;
    int regname;
    int blockType;
    pos_T start;
    pos_T end;
    int numLines;
    char_u **lines;
} yankInfo_T;

static bool isInitialized = false;
static VSClipboardGetCallback vsClipboardGetCallback = NULL;
static VSYankCallback vsYankCallback = NULL;

void VSInitialize(void) {
    if (isInitialized) {
        return;
    }

    char executable[] = "vimstickies";
    char *arguments[] = {executable, NULL};
    vimInit(1, arguments);
    vimWindowSetWidth(120);
    vimWindowSetHeight(200);
    isInitialized = true;
}

VSBufferRef VSCreateBuffer(const char *text) {
    VSInitialize();
    buf_T *buffer = vimBufferNew(0);
    VSSetText(buffer, text == NULL ? "" : text);
    return buffer;
}

void VSActivateBuffer(VSBufferRef buffer) {
    if (buffer != NULL) {
        vimBufferSetCurrent((buf_T *)buffer);
    }
}

void VSSetText(VSBufferRef bufferReference, const char *text) {
    if (bufferReference == NULL) {
        return;
    }

    const char *source = text == NULL ? "" : text;
    size_t lineCount = 1;
    for (const char *cursor = source; *cursor != '\0'; cursor++) {
        if (*cursor == '\n') {
            lineCount++;
        }
    }

    char *storage = strdup(source);
    char_u **lines = calloc(lineCount, sizeof(char_u *));
    if (storage == NULL || lines == NULL) {
        free(storage);
        free(lines);
        return;
    }

    size_t lineIndex = 0;
    lines[lineIndex++] = (char_u *)storage;
    for (char *cursor = storage; *cursor != '\0'; cursor++) {
        if (*cursor == '\n') {
            *cursor = '\0';
            lines[lineIndex++] = (char_u *)(cursor + 1);
        }
    }

    vimBufferSetCurrent((buf_T *)bufferReference);
    vimBufferSetLines((buf_T *)bufferReference, 0, -1, lines, (int)lineCount);
    free(lines);
    free(storage);
}

char *VSCopyText(VSBufferRef bufferReference) {
    if (bufferReference == NULL) {
        return strdup("");
    }

    buf_T *buffer = (buf_T *)bufferReference;
    size_t lineCount = vimBufferGetLineCount(buffer);
    size_t byteCount = lineCount > 0 ? lineCount - 1 : 0;

    for (size_t index = 0; index < lineCount; index++) {
        char_u *line = vimBufferGetLine(buffer, (linenr_T)index + 1);
        if (line != NULL) {
            byteCount += strlen((char *)line);
        }
    }

    char *result = malloc(byteCount + 1);
    if (result == NULL) {
        return NULL;
    }

    char *destination = result;
    for (size_t index = 0; index < lineCount; index++) {
        char_u *line = vimBufferGetLine(buffer, (linenr_T)index + 1);
        if (line != NULL) {
            size_t length = strlen((char *)line);
            memcpy(destination, line, length);
            destination += length;
        }
        if (index + 1 < lineCount) {
            *destination++ = '\n';
        }
    }
    *destination = '\0';
    return result;
}

void VSFree(void *pointer) {
    free(pointer);
}

void VSInput(const char *input) {
    if (input != NULL) {
        vimInput((char_u *)input);
    }
}

void VSKey(const char *key) {
    if (key != NULL) {
        vimKey((char_u *)key);
    }
}

VSMode VSGetMode(void) {
    int mode = vimGetMode();
    if ((mode & VimModeInsert) == VimModeInsert) {
        return VSModeInsert;
    }
    if ((mode & VimModeVisual) == VimModeVisual) {
        return VSModeVisual;
    }
    return VSModeNormal;
}

VSCursor VSGetCursor(void) {
    pos_T position = vimCursorGetPosition();
    VSCursor cursor = {(int)position.lnum, position.col};
    return cursor;
}

void VSSetCursor(int line, int column) {
    pos_T position = {line < 1 ? 1 : line, column < 0 ? 0 : column, 0};
    vimCursorSetPosition(position);
}

bool VSGetVisualRange(VSVisualRange *range) {
    if (range == NULL || !vimVisualIsActive()) {
        return false;
    }

    pos_T start;
    pos_T end;
    vimVisualGetRange(&start, &end);
    range->startLine = (int)start.lnum;
    range->startColumn = start.col;
    range->endLine = (int)end.lnum;
    range->endColumn = end.col;
    range->linewise = vimVisualGetType() == 'V';
    return true;
}

static int bridgeClipboardGet(int regname, int *numLines, char_u ***lines, int *blockType) {
    if (vsClipboardGetCallback == NULL) {
        return 0;
    }
    return vsClipboardGetCallback(regname, numLines, lines, blockType);
}

static void bridgeYank(yankInfo_T *yankInfo) {
    if (vsYankCallback == NULL || yankInfo == NULL) {
        return;
    }

    VSYankInfo yank;
    yank.opChar = yankInfo->op_char;
    yank.blockType = yankInfo->blockType;
    yank.numLines = yankInfo->numLines;
    yank.lines = (VSChar **)yankInfo->lines;
    vsYankCallback(&yank);
}

void VSSetClipboardGetCallback(VSClipboardGetCallback callback) {
    vsClipboardGetCallback = callback;
    vimSetClipboardGetCallback(bridgeClipboardGet);
}

void VSSetYankCallback(VSYankCallback callback) {
    vsYankCallback = callback;
    vimSetYankCallback((void (*)(void *))bridgeYank);
}
