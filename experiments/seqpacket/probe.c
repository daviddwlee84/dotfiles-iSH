/*
 * Bounded Linux AF_UNIX SOCK_SEQPACKET compatibility checks.
 *
 * Build, for example: zig cc -target x86-linux-musl -mcpu=pentium -static
 *   -std=c11 -O1 -Wall -Wextra -Werror probe.c -o seqpacket-probe
 * Run all checks, or pass one exact test name printed by --list.
 * Each check runs in a fresh child with a 15-second deadline. The parent has
 * a 240-second deadline; callers should also impose an external deadline.
 * Exit 0 means all selected checks passed; 1 means a failure; 2 is usage error.
 * This is a finite compatibility suite, not proof of complete Linux semantics.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

static const char *current_test;
static const char *executable_path;
static char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];
static volatile sig_atomic_t active_child;

static void failed(const char *expression, int line) {
    int saved = errno;
    fprintf(stderr, "FAIL %s line=%d: %s (errno=%d: %s)\n",
            current_test, line, expression, saved, strerror(saved));
    _exit(1);
}

#define CHECK(expression) do { if (!(expression)) failed(#expression, __LINE__); } while (0)

static int would_block(void) { return errno == EAGAIN || errno == EWOULDBLOCK; }

static void pair(int sockets[2], int flags) {
    CHECK(socketpair(AF_UNIX, SOCK_SEQPACKET | flags, 0, sockets) == 0);
}

static void close_pair(int sockets[2]) {
    CHECK(close(sockets[0]) == 0);
    CHECK(close(sockets[1]) == 0);
}

static void check_cloexec_nonblock(int fd) {
    int descriptor_flags = fcntl(fd, F_GETFD);
    int status_flags = fcntl(fd, F_GETFL);
    CHECK(descriptor_flags >= 0 && (descriptor_flags & FD_CLOEXEC) != 0);
    CHECK(status_flags >= 0 && (status_flags & O_NONBLOCK) != 0);
}

static short ready(int fd, short events) {
    struct pollfd pfd = {.fd = fd, .events = events};
    CHECK(poll(&pfd, 1, 0) >= 0);
    return pfd.revents;
}

static int selected(int fd, int write_ready) {
    fd_set set;
    struct timeval tv = {0};
    FD_ZERO(&set);
    CHECK(fd < FD_SETSIZE);
    FD_SET(fd, &set);
    int count = select(fd + 1, write_ready ? NULL : &set,
                       write_ready ? &set : NULL, NULL, &tv);
    CHECK(count >= 0);
    return count == 1 && FD_ISSET(fd, &set);
}

static void socketpair_flags(void) {
    int sockets[2];
    pair(sockets, SOCK_CLOEXEC | SOCK_NONBLOCK);
    for (int i = 0; i < 2; i++) {
        check_cloexec_nonblock(sockets[i]);
        int type = -1;
        socklen_t length = sizeof(type);
        CHECK(getsockopt(sockets[i], SOL_SOCKET, SO_TYPE, &type, &length) == 0);
        CHECK(length == sizeof(type) && type == SOCK_SEQPACKET);
    }
    close_pair(sockets);
}

static void raw_socketpair_flags(void) {
    int sockets[2] = {-1, -1};
    /* musl can retry failed flagged calls and hide a kernel translation bug. */
#if defined(__i386__) && defined(SYS_socketcall)
    unsigned long args[] = {AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC | SOCK_NONBLOCK,
                            0, (unsigned long)sockets};
    CHECK(syscall(SYS_socketcall, 8, args) == 0);
#elif defined(SYS_socketpair)
    CHECK(syscall(SYS_socketpair, AF_UNIX,
                  SOCK_SEQPACKET | SOCK_CLOEXEC | SOCK_NONBLOCK, 0, sockets) == 0);
#else
#error "A Linux raw socketpair syscall is required for this check"
#endif
    for (int i = 0; i < 2; i++) {
        check_cloexec_nonblock(sockets[i]);
    }
    close_pair(sockets);
}

static void record_boundaries(void) {
    int sockets[2];
    char buf[32] = {0};
    pair(sockets, 0);
    CHECK(write(sockets[0], "abc", 3) == 3);
    CHECK(send(sockets[0], "defgh", 5, 0) == 5);
    CHECK(read(sockets[1], buf, sizeof(buf)) == 3);
    CHECK(memcmp(buf, "abc", 3) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 5);
    CHECK(memcmp(buf, "defgh", 5) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_DONTWAIT) == -1 && would_block());
    close_pair(sockets);
}

static void peek_and_truncation(void) {
    int sockets[2];
    char buf[16] = {0};
    struct iovec iov = {.iov_base = buf, .iov_len = 2};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1};
    pair(sockets, 0);
    CHECK(send(sockets[0], "abcdef", 6, 0) == 6);
    CHECK(recvmsg(sockets[1], &msg, MSG_PEEK) == 2);
    CHECK((msg.msg_flags & MSG_TRUNC) != 0 && memcmp(buf, "ab", 2) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_PEEK) == 6);
    CHECK(memcmp(buf, "abcdef", 6) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 6);
    CHECK(send(sockets[0], "abcdef", 6, 0) == 6);
    CHECK(send(sockets[0], "next", 4, 0) == 4);
    msg.msg_flags = 0;
    CHECK(recvmsg(sockets[1], &msg, 0) == 2);
    CHECK((msg.msg_flags & MSG_TRUNC) != 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 4);
    CHECK(memcmp(buf, "next", 4) == 0);
    close_pair(sockets);
}

static void input_msg_trunc(void) {
    int sockets[2];
    char buf[2];
    pair(sockets, 0);
    CHECK(send(sockets[0], "abcdef", 6, 0) == 6);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_PEEK | MSG_TRUNC) == 6);
    CHECK(memcmp(buf, "ab", 2) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_TRUNC) == 6);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_DONTWAIT) == -1 && would_block());
    close_pair(sockets);
}

static void scatter_gather_record(void) {
    int sockets[2];
    char first[2] = {0}, second[8] = {0};
    struct iovec out[] = {{.iov_base = "abc", .iov_len = 3},
                          {.iov_base = "def", .iov_len = 3}};
    struct iovec in[] = {{.iov_base = first, .iov_len = sizeof(first)},
                         {.iov_base = second, .iov_len = sizeof(second)}};
    struct msghdr tx = {.msg_iov = out, .msg_iovlen = 2};
    struct msghdr rx = {.msg_iov = in, .msg_iovlen = 2};
    pair(sockets, 0);
    CHECK(sendmsg(sockets[0], &tx, 0) == 6);
    CHECK(recvmsg(sockets[1], &rx, 0) == 6);
    CHECK(memcmp(first, "ab", 2) == 0 && memcmp(second, "cdef", 4) == 0);
    CHECK((rx.msg_flags & MSG_TRUNC) == 0);
    close_pair(sockets);
}

static void vectored_io_record(void) {
    int sockets[2];
    char first[2] = {0}, second[8] = {0}, buf[16];
    struct iovec out[] = {{.iov_base = "abc", .iov_len = 3},
                          {.iov_base = "def", .iov_len = 3}};
    struct iovec in[] = {{.iov_base = first, .iov_len = sizeof(first)},
                         {.iov_base = second, .iov_len = sizeof(second)}};
    pair(sockets, 0);
    CHECK(writev(sockets[0], out, 2) == 6);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 6 && memcmp(buf, "abcdef", 6) == 0);
    CHECK(send(sockets[0], "abcdef", 6, 0) == 6);
    CHECK(send(sockets[0], "next", 4, 0) == 4);
    CHECK(readv(sockets[1], in, 2) == 6);
    CHECK(memcmp(first, "ab", 2) == 0 && memcmp(second, "cdef", 4) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 4 && memcmp(buf, "next", 4) == 0);
    close_pair(sockets);
}

static void waitall_record_boundary(void) {
    int sockets[2];
    char buf[32];
    pair(sockets, 0);
    CHECK(send(sockets[0], "abc", 3, 0) == 3);
    /* WAITALL must stop at a record boundary, even while the peer stays open. */
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_WAITALL) == 3);
    CHECK(memcmp(buf, "abc", 3) == 0);
    close_pair(sockets);
}

static void zero_length_record(void) {
    int sockets[2];
    char buf[8];
    pair(sockets, 0);
    CHECK(send(sockets[0], "", 0, 0) == 0);
    CHECK((ready(sockets[1], POLLIN) & POLLIN) != 0);
    CHECK(send(sockets[0], "after", 5, 0) == 5);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 5);
    CHECK(memcmp(buf, "after", 5) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), MSG_DONTWAIT) == -1 && would_block());
    close_pair(sockets);
}

static void close_eof(void) {
    int sockets[2];
    char buf[8];
    pair(sockets, 0);
    CHECK(send(sockets[0], "last", 4, 0) == 4);
    CHECK(close(sockets[0]) == 0);
    short events = ready(sockets[1], POLLIN);
    CHECK((events & POLLIN) != 0 && (events & POLLHUP) != 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 4);
    CHECK(memcmp(buf, "last", 4) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 0);
    CHECK(selected(sockets[1], 0));
    CHECK(send(sockets[1], "x", 1, MSG_NOSIGNAL) == -1 && errno == EPIPE);
    CHECK(close(sockets[1]) == 0);
}

static void shutdown_half_close(void) {
    int sockets[2];
    char buf[8];
    pair(sockets, 0);
    CHECK(send(sockets[0], "last", 4, 0) == 4);
    CHECK(shutdown(sockets[0], SHUT_WR) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 4);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 0);
    CHECK(send(sockets[1], "reply", 5, MSG_NOSIGNAL) == 5);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 5);
    CHECK(memcmp(buf, "reply", 5) == 0);
    CHECK(send(sockets[0], "x", 1, MSG_NOSIGNAL) == -1 && errno == EPIPE);
    close_pair(sockets);
}

static void nonblocking_poll_select(void) {
    int sockets[2];
    char buf[8];
    pair(sockets, SOCK_NONBLOCK);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == -1 && would_block());
    CHECK((ready(sockets[1], POLLIN) & POLLIN) == 0);
    CHECK(!selected(sockets[1], 0));
    CHECK((ready(sockets[0], POLLOUT) & POLLOUT) != 0);
    CHECK(selected(sockets[0], 1));
    CHECK(send(sockets[0], "ready", 5, 0) == 5);
    CHECK((ready(sockets[1], POLLIN) & POLLIN) != 0);
    CHECK(selected(sockets[1], 0));
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 5);
    CHECK(!selected(sockets[1], 0));
    close_pair(sockets);
}

static void bounded_backpressure(void) {
    int sockets[2];
    char payload[1024], buf[sizeof(payload)];
    int buffer_size = 4096, count = 0;
    memset(payload, 'q', sizeof(payload));
    pair(sockets, SOCK_NONBLOCK);
    CHECK(setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF,
                     &buffer_size, sizeof(buffer_size)) == 0);
    /* At most 1 MiB, with no loops contingent on unbounded peer activity. */
    for (; count < 1024; count++) {
        ssize_t n = send(sockets[0], payload, sizeof(payload), MSG_NOSIGNAL);
        if (n == -1) {
            CHECK(would_block());
            break;
        }
        CHECK(n == sizeof(payload));
    }
    CHECK(count > 0 && count < 1024);
    CHECK((ready(sockets[0], POLLOUT) & POLLOUT) == 0);
    CHECK(!selected(sockets[0], 1));
    CHECK((ready(sockets[1], POLLIN) & POLLIN) != 0);
    for (int i = 0; i < count; i++) {
        CHECK(recv(sockets[1], buf, sizeof(buf), 0) == sizeof(buf));
        CHECK(memcmp(buf, payload, sizeof(buf)) == 0);
    }
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == -1 && would_block());
    CHECK((ready(sockets[0], POLLOUT) & POLLOUT) != 0);
    CHECK(selected(sockets[0], 1));
    close_pair(sockets);
}

static void blocking_poll_wakeup(void) {
    int sockets[2], sync_pipe[2];
    char buf;
    pair(sockets, 0);
    CHECK(pipe(sync_pipe) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(sockets[0]) == 0 && close(sync_pipe[1]) == 0);
        CHECK(read(sync_pipe[0], &buf, 1) == 1);
        CHECK(usleep(50000) == 0);
        CHECK(send(sockets[1], "x", 1, 0) == 1);
        CHECK(close(sockets[1]) == 0 && close(sync_pipe[0]) == 0);
        _exit(0);
    }
    CHECK(close(sockets[1]) == 0 && close(sync_pipe[0]) == 0);
    CHECK((ready(sockets[0], POLLIN) & POLLIN) == 0);
    CHECK(write(sync_pipe[1], "x", 1) == 1);
    struct pollfd pfd = {.fd = sockets[0], .events = POLLIN};
    CHECK(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN) != 0);
    CHECK(recv(sockets[0], &buf, 1, 0) == 1 && buf == 'x');
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(sockets[0]) == 0 && close(sync_pipe[1]) == 0);
}

static void send_rights(int socket, const int *fds, size_t count) {
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(3 * sizeof(int))];
    } control = {0};
    struct iovec iov = {.iov_base = "R", .iov_len = 1};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1,
                         .msg_control = control.bytes,
                         .msg_controllen = CMSG_SPACE(count * sizeof(int))};
    CHECK(count > 0 && count <= 3);
    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    CHECK(cmsg != NULL);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(count * sizeof(int));
    memcpy(CMSG_DATA(cmsg), fds, count * sizeof(int));
    CHECK(sendmsg(socket, &msg, MSG_NOSIGNAL) == 1);
}

/* Zig 0.15.2's bundled musl macro mixes size_t and ptrdiff_t internally. */
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-compare"
static struct cmsghdr *next_control(struct msghdr *msg, struct cmsghdr *cmsg) {
    return CMSG_NXTHDR(msg, cmsg);
}
#pragma GCC diagnostic pop

static size_t receive_rights(int socket, int flags, size_t control_size,
                             int *fds, int *message_flags) {
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(3 * sizeof(int))];
    } control = {0};
    char payload = 0;
    struct iovec iov = {.iov_base = &payload, .iov_len = 1};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1,
                         .msg_control = control_size ? control.bytes : NULL,
                         .msg_controllen = control_size};
    CHECK(control_size <= sizeof(control.bytes));
    CHECK(recvmsg(socket, &msg, flags) == 1);
    CHECK(payload == 'R');
    size_t count = 0;
    for (struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg); cmsg;
         cmsg = next_control(&msg, cmsg)) {
        CHECK(cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS);
        CHECK(cmsg->cmsg_len >= CMSG_LEN(0));
        size_t bytes = cmsg->cmsg_len - CMSG_LEN(0);
        CHECK(bytes % sizeof(int) == 0 && count + bytes / sizeof(int) <= 3);
        memcpy(fds + count, CMSG_DATA(cmsg), bytes);
        count += bytes / sizeof(int);
    }
    *message_flags = msg.msg_flags;
    return count;
}

static void rights_transfer_mode(int receive_flags) {
    int sockets[2], pipes[2], received[3], flags;
    char buf;
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    send_rights(sockets[0], &pipes[1], 1);
    CHECK(close(pipes[1]) == 0);
    CHECK(receive_rights(sockets[1], receive_flags, CMSG_SPACE(sizeof(int)),
                         received, &flags) == 1);
    CHECK((flags & MSG_CTRUNC) == 0);
    int fd_flags = fcntl(received[0], F_GETFD);
    CHECK(fd_flags >= 0);
    CHECK((fd_flags & FD_CLOEXEC) == (receive_flags ? FD_CLOEXEC : 0));
    CHECK(write(received[0], "x", 1) == 1);
    CHECK(read(pipes[0], &buf, 1) == 1 && buf == 'x');
    CHECK(close(received[0]) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0);
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void rights_transfer(void) { rights_transfer_mode(0); }
static void rights_cloexec(void) { rights_transfer_mode(MSG_CMSG_CLOEXEC); }

static void rights_peek(void) {
    int sockets[2], pipes[2], received[3][3], flags;
    char buf;
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    send_rights(sockets[0], &pipes[1], 1);
    CHECK(close(pipes[1]) == 0);
    for (int i = 0; i < 3; i++) {
        CHECK(receive_rights(sockets[1], i < 2 ? MSG_PEEK : 0,
                             CMSG_SPACE(sizeof(int)), received[i], &flags) == 1);
        CHECK((flags & MSG_CTRUNC) == 0);
        for (int j = 0; j < i; j++) CHECK(received[i][0] != received[j][0]);
        CHECK(write(received[i][0], "x", 1) == 1);
        CHECK(read(pipes[0], &buf, 1) == 1 && buf == 'x');
    }
    for (int i = 0; i < 3; i++) CHECK(close(received[i][0]) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0);
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void rights_control_truncation(void) {
    int sockets[2], pipes[2], received[3], flags;
    char buf;
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    int sent[] = {pipes[1], pipes[1], pipes[1]};
    send_rights(sockets[0], sent, 3);
    CHECK(close(pipes[1]) == 0);
    /* CMSG_SPACE may fit two descriptors on 64-bit; use exact CMSG_LEN. */
    CHECK(receive_rights(sockets[1], 0, CMSG_LEN(sizeof(int)), received, &flags) == 1);
    CHECK((flags & MSG_CTRUNC) != 0);
    CHECK(close(received[0]) == 0);
    CHECK(fcntl(pipes[0], F_SETFL, O_NONBLOCK) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0); /* Excess rights must be released. */
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void rights_no_control_buffer(void) {
    int sockets[2], pipes[2], received[3], flags;
    char buf;
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    send_rights(sockets[0], &pipes[1], 1);
    CHECK(close(pipes[1]) == 0);
    CHECK(receive_rights(sockets[1], 0, 0, received, &flags) == 0);
    CHECK((flags & MSG_CTRUNC) != 0);
    CHECK(fcntl(pipes[0], F_SETFL, O_NONBLOCK) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0);
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void rights_discarded_by_read(void) {
    int sockets[2], pipes[2];
    char buf;
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    send_rights(sockets[0], &pipes[1], 1);
    CHECK(close(pipes[1]) == 0);
    CHECK(read(sockets[1], &buf, 1) == 1 && buf == 'R');
    CHECK(fcntl(pipes[0], F_SETFL, O_NONBLOCK) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0); /* No inaccessible live writer. */
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void peer_credentials(void) {
    int sockets[2];
    pair(sockets, 0);
    struct ucred credentials = {0};
    socklen_t size = sizeof(credentials);
    CHECK(getsockopt(sockets[0], SOL_SOCKET, SO_PEERCRED, &credentials, &size) == 0);
    CHECK(size == sizeof(credentials));
    CHECK(credentials.pid == getpid());
    CHECK(credentials.uid == getuid() && credentials.gid == getgid());
    close_pair(sockets);
}

static void message_credentials(void) {
    int sockets[2], enabled = 1;
    pair(sockets, 0);
    CHECK(setsockopt(sockets[1], SOL_SOCKET, SO_PASSCRED, &enabled, sizeof(enabled)) == 0);
    CHECK(send(sockets[0], "C", 1, 0) == 1);
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(sizeof(struct ucred))];
    } control = {0};
    char buf = 0;
    struct iovec iov = {.iov_base = &buf, .iov_len = 1};
    struct msghdr msg = {.msg_iov = &iov, .msg_iovlen = 1,
                         .msg_control = control.bytes, .msg_controllen = sizeof(control.bytes)};
    CHECK(recvmsg(sockets[1], &msg, 0) == 1 && buf == 'C');
    CHECK((msg.msg_flags & MSG_CTRUNC) == 0);
    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    CHECK(cmsg != NULL && cmsg->cmsg_level == SOL_SOCKET);
    CHECK(cmsg->cmsg_type == SCM_CREDENTIALS && cmsg->cmsg_len == CMSG_LEN(sizeof(struct ucred)));
    struct ucred credentials;
    memcpy(&credentials, CMSG_DATA(cmsg), sizeof(credentials));
    CHECK(credentials.pid == getpid());
    CHECK(credentials.uid == getuid() && credentials.gid == getgid());
    close_pair(sockets);
}

static void pathname_connection(void) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    CHECK(strlen(socket_path) < sizeof(address.sun_path));
    strcpy(address.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    int listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    CHECK(listener >= 0);
    CHECK(bind(listener, (struct sockaddr *)&address, size) == 0);
    CHECK(listen(listener, 2) == 0);
    /* A normal local connect queues immediately; no network or external peer. */
    int client = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(client >= 0);
    CHECK(connect(client, (struct sockaddr *)&address, size) == 0);
    CHECK((ready(listener, POLLIN) & POLLIN) != 0);
    int accepted = accept4(listener, NULL, NULL, SOCK_CLOEXEC | SOCK_NONBLOCK);
    CHECK(accepted >= 0);
    check_cloexec_nonblock(accepted);
    char buf[16];
    CHECK(send(client, "client", 6, 0) == 6);
    CHECK(recv(accepted, buf, sizeof(buf), 0) == 6 && memcmp(buf, "client", 6) == 0);
    CHECK(send(accepted, "server", 6, 0) == 6);
    CHECK(recv(client, buf, sizeof(buf), 0) == 6 && memcmp(buf, "server", 6) == 0);
    CHECK(close(accepted) == 0);
    CHECK(recv(client, buf, sizeof(buf), 0) == 0);
    CHECK(close(client) == 0 && close(listener) == 0);
    CHECK(unlink(socket_path) == 0);
}

static void fork_transfer(void) {
    int sockets[2];
    char buf[8];
    pair(sockets, SOCK_CLOEXEC);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(sockets[0]) == 0);
        CHECK(send(sockets[1], "child", 5, 0) == 5);
        CHECK(close(sockets[1]) == 0);
        _exit(0);
    }
    CHECK(close(sockets[1]) == 0);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 5 && memcmp(buf, "child", 5) == 0);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 0);
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(sockets[0]) == 0);
}

static void abstract_names(void) {
    struct sockaddr_un names[2] = {{.sun_family = AF_UNIX}, {.sun_family = AF_UNIX}};
    int n = snprintf(names[0].sun_path + 1, sizeof(names[0].sun_path) - 3,
                     "ish-seqpacket-%ld", (long)getpid());
    CHECK(n > 0 && n < (int)sizeof(names[0].sun_path) - 3);
    size_t bytes = (size_t)n + 3; /* Initial NUL, visible prefix, embedded NUL, suffix. */
    names[0].sun_path[bytes - 1] = 'a';
    names[1] = names[0];
    names[1].sun_path[bytes - 1] = 'b';
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + bytes);
    int listeners[2];
    for (int i = 0; i < 2; i++) {
        listeners[i] = socket(AF_UNIX, SOCK_SEQPACKET, 0);
        CHECK(listeners[i] >= 0);
        CHECK(bind(listeners[i], (struct sockaddr *)&names[i], size) == 0);
        CHECK(listen(listeners[i], 1) == 0);
        struct sockaddr_un actual = {0};
        socklen_t actual_size = sizeof(actual);
        CHECK(getsockname(listeners[i], (struct sockaddr *)&actual, &actual_size) == 0);
        CHECK(actual_size == size && memcmp(&actual, &names[i], size) == 0);
        memset(&actual, 0, sizeof(actual));
        actual_size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + 3);
        CHECK(getsockname(listeners[i], (struct sockaddr *)&actual, &actual_size) == 0);
        CHECK(actual_size == size && memcmp(&actual, &names[i], offsetof(struct sockaddr_un, sun_path) + 3) == 0);
    }
    int client = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(client >= 0 && connect(client, (struct sockaddr *)&names[0], size) == 0);
    CHECK((ready(listeners[0], POLLIN) & POLLIN) != 0);
    CHECK((ready(listeners[1], POLLIN) & POLLIN) == 0);
    struct sockaddr_un actual = {0};
    socklen_t actual_size = sizeof(actual);
    CHECK(getpeername(client, (struct sockaddr *)&actual, &actual_size) == 0);
    CHECK(actual_size == size && memcmp(&actual, &names[0], size) == 0);
    int accepted = accept(listeners[0], NULL, NULL);
    CHECK(accepted >= 0);
    CHECK(close(client) == 0 && close(accepted) == 0);
    CHECK(close(listeners[0]) == 0 && close(listeners[1]) == 0);
}

static void accept_default_flags(void) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strcpy(address.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    int listener = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
    CHECK(listener >= 0);
    CHECK(bind(listener, (struct sockaddr *)&address, size) == 0 && listen(listener, 1) == 0);
    CHECK(accept4(listener, NULL, NULL, 0) == -1 && would_block());
    int client = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(client >= 0 && connect(client, (struct sockaddr *)&address, size) == 0);
    int accepted = accept4(listener, NULL, NULL, 0);
    CHECK(accepted >= 0);
    int descriptor_flags = fcntl(accepted, F_GETFD), status_flags = fcntl(accepted, F_GETFL);
    CHECK(descriptor_flags >= 0 && (descriptor_flags & FD_CLOEXEC) == 0);
    CHECK(status_flags >= 0 && (status_flags & O_NONBLOCK) == 0);
    CHECK(close(accepted) == 0 && close(client) == 0 && close(listener) == 0);
    CHECK(unlink(socket_path) == 0);
}

static void cloexec_eof(void) {
    int sockets[2];
    pair(sockets, SOCK_CLOEXEC);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(sockets[0]) == 0);
        char fd_text[32];
        CHECK(snprintf(fd_text, sizeof(fd_text), "%d", sockets[1]) > 0);
        char *args[] = {(char *)executable_path, "--exec-check-closed", fd_text, NULL};
        execvp(executable_path, args);
        failed("execvp self", __LINE__);
    }
    CHECK(close(sockets[1]) == 0);
    struct pollfd pfd = {.fd = sockets[0], .events = POLLIN};
    CHECK(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN) != 0);
    char buf;
    CHECK(recv(sockets[0], &buf, 1, 0) == 0);
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(sockets[0]) == 0);
}

static volatile sig_atomic_t sigpipe_count;
static void count_sigpipe(int signal_number) { (void)signal_number; sigpipe_count++; }

static void seqpacket_sigpipe_behavior(void) {
    int sockets[2];
    pair(sockets, 0);
    struct sigaction sa = {.sa_handler = count_sigpipe};
    sigemptyset(&sa.sa_mask);
    CHECK(sigaction(SIGPIPE, &sa, NULL) == 0);
    CHECK(close(sockets[1]) == 0);
    CHECK(send(sockets[0], "x", 1, MSG_NOSIGNAL) == -1 && errno == EPIPE);
    CHECK(sigpipe_count == 0);
    CHECK(send(sockets[0], "x", 1, 0) == -1 && errno == EPIPE);
    /* Linux AF_UNIX SEQPACKET uses the datagram send path. Unlike STREAM,
     * its EPIPE path does not generate SIGPIPE, even without MSG_NOSIGNAL.
     * Reference: Linux v6.10 net/unix/af_unix.c unix_seqpacket_sendmsg. */
    CHECK(sigpipe_count == 0);
    CHECK(write(sockets[0], "x", 1) == -1 && errno == EPIPE);
    CHECK(sigpipe_count == 0);
    CHECK(close(sockets[0]) == 0);
}

static void blocking_receive_wakeup(void) {
    int sockets[2], sync_pipe[2];
    pair(sockets, 0);
    CHECK(pipe(sync_pipe) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(sockets[0]) == 0 && close(sync_pipe[1]) == 0);
        char signal_byte;
        CHECK(read(sync_pipe[0], &signal_byte, 1) == 1);
        CHECK(usleep(50000) == 0);
        CHECK(send(sockets[1], "x", 1, 0) == 1);
        CHECK(close(sockets[1]) == 0 && close(sync_pipe[0]) == 0);
        _exit(0);
    }
    CHECK(close(sockets[1]) == 0 && close(sync_pipe[0]) == 0);
    CHECK((ready(sockets[0], POLLIN) & POLLIN) == 0);
    CHECK(write(sync_pipe[1], "x", 1) == 1);
    char buf;
    CHECK(recv(sockets[0], &buf, 1, 0) == 1 && buf == 'x');
    int status;
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(sockets[0]) == 0 && close(sync_pipe[1]) == 0);
}

static void shutdown_read_queued(void) {
    int sockets[2];
    char buf[16];
    pair(sockets, 0);
    CHECK(send(sockets[0], "queued", 6, 0) == 6);
    CHECK(shutdown(sockets[1], SHUT_RD) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 6 && memcmp(buf, "queued", 6) == 0);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 0);
    CHECK(send(sockets[0], "x", 1, MSG_NOSIGNAL) == -1 && errno == EPIPE);
    CHECK(send(sockets[1], "reply", 5, MSG_NOSIGNAL) == 5);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 5 && memcmp(buf, "reply", 5) == 0);
    close_pair(sockets);
}

static void zero_data_rights(void) {
    int sockets[2], pipes[2];
    pair(sockets, 0);
    CHECK(pipe(pipes) == 0);
    union {
        struct cmsghdr align;
        unsigned char bytes[CMSG_SPACE(sizeof(int))];
    } control = {0};
    struct msghdr msg = {.msg_control = control.bytes, .msg_controllen = sizeof(control.bytes)};
    struct cmsghdr *cmsg = CMSG_FIRSTHDR(&msg);
    CHECK(cmsg != NULL);
    cmsg->cmsg_level = SOL_SOCKET;
    cmsg->cmsg_type = SCM_RIGHTS;
    cmsg->cmsg_len = CMSG_LEN(sizeof(int));
    memcpy(CMSG_DATA(cmsg), &pipes[1], sizeof(int));
    CHECK(sendmsg(sockets[0], &msg, 0) == 0);
    CHECK(close(pipes[1]) == 0);
    CHECK((ready(sockets[1], POLLIN) & POLLIN) != 0);
    memset(control.bytes, 0, sizeof(control.bytes));
    msg.msg_controllen = sizeof(control.bytes);
    CHECK(recvmsg(sockets[1], &msg, MSG_CMSG_CLOEXEC) == 0);
    CHECK((msg.msg_flags & MSG_CTRUNC) == 0);
    cmsg = CMSG_FIRSTHDR(&msg);
    CHECK(cmsg != NULL && cmsg->cmsg_level == SOL_SOCKET && cmsg->cmsg_type == SCM_RIGHTS);
    CHECK(cmsg->cmsg_len == CMSG_LEN(sizeof(int)));
    int received;
    memcpy(&received, CMSG_DATA(cmsg), sizeof(received));
    int descriptor_flags = fcntl(received, F_GETFD);
    CHECK(descriptor_flags >= 0 && (descriptor_flags & FD_CLOEXEC) != 0);
    CHECK(write(received, "x", 1) == 1);
    char buf;
    CHECK(read(pipes[0], &buf, 1) == 1 && buf == 'x');
    CHECK(close(received) == 0);
    CHECK(read(pipes[0], &buf, 1) == 0);
    CHECK(close(pipes[0]) == 0);
    close_pair(sockets);
}

static void fionread_queued_bytes(void) {
    int sockets[2], available = -1;
    char buf[16];
    pair(sockets, 0);
    CHECK(ioctl(sockets[1], FIONREAD, &available) == 0 && available == 0);
    CHECK(send(sockets[0], "abc", 3, 0) == 3);
    CHECK(send(sockets[0], "defgh", 5, 0) == 5);
    /* Linux unix_inq_len sums queued bytes for STREAM and SEQPACKET. */
    CHECK(ioctl(sockets[1], FIONREAD, &available) == 0 && available == 8);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 3);
    CHECK(ioctl(sockets[1], FIONREAD, &available) == 0 && available == 5);
    CHECK(recv(sockets[1], buf, sizeof(buf), 0) == 5);
    CHECK(ioctl(sockets[1], FIONREAD, &available) == 0 && available == 0);
    close_pair(sockets);
}

static long long monotonic_milliseconds(void) {
    struct timespec now;
    CHECK(clock_gettime(CLOCK_MONOTONIC, &now) == 0);
    return (long long)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static void receive_timeout(void) {
    int sockets[2];
    pair(sockets, 0);
    struct timeval deadline = {.tv_sec = 0, .tv_usec = 200000}, actual = {0};
    CHECK(setsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &deadline, sizeof(deadline)) == 0);
    socklen_t size = sizeof(actual);
    CHECK(getsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &actual, &size) == 0);
    CHECK(size == sizeof(actual) && (actual.tv_sec > 0 || actual.tv_usec > 0));
    long long before = monotonic_milliseconds();
    char buf;
    CHECK(recv(sockets[1], &buf, 1, 0) == -1 && would_block());
    long long elapsed = monotonic_milliseconds() - before;
    CHECK(elapsed >= 50 && elapsed < 5000);
    close_pair(sockets);
}

static void send_timeout(void) {
    int sockets[2], buffer_size = 4096;
    char payload[1024];
    memset(payload, 't', sizeof(payload));
    pair(sockets, 0);
    CHECK(setsockopt(sockets[0], SOL_SOCKET, SO_SNDBUF, &buffer_size, sizeof(buffer_size)) == 0);
    struct timeval deadline = {.tv_sec = 0, .tv_usec = 200000};
    CHECK(setsockopt(sockets[0], SOL_SOCKET, SO_SNDTIMEO, &deadline, sizeof(deadline)) == 0);
    int count = 0;
    for (; count < 1024; count++) {
        ssize_t n = send(sockets[0], payload, sizeof(payload), MSG_DONTWAIT | MSG_NOSIGNAL);
        if (n < 0) { CHECK(would_block()); break; }
        CHECK(n == sizeof(payload));
    }
    CHECK(count > 0 && count < 1024);
    long long before = monotonic_milliseconds();
    CHECK(send(sockets[0], payload, sizeof(payload), MSG_NOSIGNAL) == -1 && would_block());
    long long elapsed = monotonic_milliseconds() - before;
    CHECK(elapsed >= 50 && elapsed < 5000);
    close_pair(sockets);
}

static void listener_full_connect_wakeup(void) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strcpy(address.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    int listener = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(listener >= 0 && bind(listener, (struct sockaddr *)&address, size) == 0);
    CHECK(listen(listener, 0) == 0); /* Linux allows one pending connection. */
    int first = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(first >= 0 && connect(first, (struct sockaddr *)&address, size) == 0);
    int nonblocking = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_NONBLOCK, 0);
    CHECK(nonblocking >= 0);
    CHECK(connect(nonblocking, (struct sockaddr *)&address, size) == -1 && would_block());
    CHECK(close(nonblocking) == 0);
    int sync_pipe[2];
    CHECK(pipe(sync_pipe) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(listener) == 0 && close(first) == 0 && close(sync_pipe[0]) == 0);
        int client = socket(AF_UNIX, SOCK_SEQPACKET, 0);
        CHECK(client >= 0);
        CHECK(write(sync_pipe[1], "x", 1) == 1);
        CHECK(connect(client, (struct sockaddr *)&address, size) == 0);
        CHECK(send(client, "connected", 9, 0) == 9);
        CHECK(close(client) == 0 && close(sync_pipe[1]) == 0);
        _exit(0);
    }
    CHECK(close(sync_pipe[1]) == 0);
    char buf[16];
    CHECK(read(sync_pipe[0], buf, 1) == 1);
    CHECK(usleep(50000) == 0);
    int status;
    CHECK(waitpid(child, &status, WNOHANG) == 0); /* Connect is still blocked. */
    int accepted_first = accept(listener, NULL, NULL);
    CHECK(accepted_first >= 0);
    CHECK(close(accepted_first) == 0 && close(first) == 0);
    struct pollfd pfd = {.fd = listener, .events = POLLIN};
    CHECK(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN) != 0);
    int accepted_second = accept(listener, NULL, NULL);
    CHECK(accepted_second >= 0);
    CHECK(recv(accepted_second, buf, sizeof(buf), 0) == 9 && memcmp(buf, "connected", 9) == 0);
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(accepted_second) == 0 && close(listener) == 0 && close(sync_pipe[0]) == 0);
    CHECK(unlink(socket_path) == 0);
}

static void noncyclic_socket_rights(void) {
    int carrier[2], transported[2], received[3], flags;
    pair(carrier, 0);
    pair(transported, 0);
    send_rights(carrier[0], &transported[0], 1);
    CHECK(close(transported[0]) == 0);
    CHECK(receive_rights(carrier[1], MSG_CMSG_CLOEXEC, CMSG_SPACE(sizeof(int)), received, &flags) == 1);
    CHECK((flags & MSG_CTRUNC) == 0);
    CHECK(send(transported[1], "x", 1, 0) == 1);
    char buf;
    CHECK(recv(received[0], &buf, 1, 0) == 1 && buf == 'x');
    CHECK(close(received[0]) == 0);
    CHECK(recv(transported[1], &buf, 1, 0) == 0);
    CHECK(close(transported[1]) == 0);
    close_pair(carrier);
}

static void close_unread_reset(void) {
    int sockets[2];
    char buf[16];
    pair(sockets, 0);
    CHECK(send(sockets[0], "unread", 6, 0) == 6);
    CHECK(send(sockets[1], "reply", 5, 0) == 5);
    CHECK(close(sockets[1]) == 0);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == -1 && errno == ECONNRESET);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 5 && memcmp(buf, "reply", 5) == 0);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 0);
    CHECK(close(sockets[0]) == 0);
}

static long raw_set_option(int fd, int option, void *value, socklen_t size) {
#if defined(__i386__) && defined(SYS_socketcall)
    unsigned long args[] = {(unsigned long)fd, SOL_SOCKET, (unsigned long)option,
                            (unsigned long)value, size};
    return syscall(SYS_socketcall, 14, args);
#else
    return syscall(SYS_setsockopt, fd, SOL_SOCKET, option, value, size);
#endif
}

static long raw_get_option(int fd, int option, void *value, socklen_t *size) {
#if defined(__i386__) && defined(SYS_socketcall)
    unsigned long args[] = {(unsigned long)fd, SOL_SOCKET, (unsigned long)option,
                            (unsigned long)value, (unsigned long)size};
    return syscall(SYS_socketcall, 15, args);
#else
    return syscall(SYS_getsockopt, fd, SOL_SOCKET, option, value, size);
#endif
}

static void raw_time64_options(void) {
    int sockets[2];
    pair(sockets, 0);
    /* Linux i386 and asm-generic SO_RCVTIMEO_NEW / SO_SNDTIMEO_NEW ABI.
     * Raw calls ensure a musl retry with legacy timeval cannot hide absence. */
    int options[] = {66, 67};
    struct { int64_t seconds, microseconds; } requested = {1, 250000}, actual;
    for (size_t i = 0; i < sizeof(options) / sizeof(options[0]); i++) {
        CHECK(raw_set_option(sockets[0], options[i], &requested, sizeof(requested)) == 0);
        memset(&actual, 0, sizeof(actual));
        socklen_t size = sizeof(actual);
        CHECK(raw_get_option(sockets[0], options[i], &actual, &size) == 0);
        CHECK(size == sizeof(actual));
        CHECK(actual.seconds == 1 && actual.microseconds >= 250000 && actual.microseconds < 1000000);
    }
    close_pair(sockets);
}

static void sendto_connected_destination(void) {
    int sockets[2];
    pair(sockets, 0);
    struct sockaddr_un ignored = {.sun_family = AF_UNIX};
    strcpy(ignored.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    /* Linux ignores a supplied destination for connected AF_UNIX SEQPACKET. */
    CHECK(sendto(sockets[0], "x", 1, 0, (struct sockaddr *)&ignored, size) == 1);
    char buf;
    CHECK(recv(sockets[1], &buf, 1, 0) == 1 && buf == 'x');
    close_pair(sockets);
}

static void recvfrom_unnamed_sender(void) {
    int sockets[2];
    pair(sockets, 0);
    struct sockaddr_un sender = {0};
    socklen_t size = sizeof(sender);
    char buf;
    CHECK(send(sockets[0], "x", 1, 0) == 1);
    CHECK(recvfrom(sockets[1], &buf, 1, 0, (struct sockaddr *)&sender, &size) == 1 && buf == 'x');
    CHECK(size == 0); /* Different from getpeername, whose unnamed length is 2. */
    size = sizeof(sender);
    CHECK(getpeername(sockets[1], (struct sockaddr *)&sender, &size) == 0);
    CHECK(size == offsetof(struct sockaddr_un, sun_path) && sender.sun_family == AF_UNIX);
    close_pair(sockets);
}

static void pending_reset_send(void) {
    int sockets[2];
    pair(sockets, 0);
    CHECK(send(sockets[0], "unread", 6, 0) == 6);
    CHECK(close(sockets[1]) == 0);
    CHECK((ready(sockets[0], POLLIN | POLLOUT) & POLLERR) != 0);
    CHECK(send(sockets[0], "x", 1, MSG_NOSIGNAL) == -1 && errno == ECONNRESET);
    CHECK((ready(sockets[0], POLLIN | POLLOUT) & POLLERR) == 0);
    CHECK(send(sockets[0], "x", 1, MSG_NOSIGNAL) == -1 && errno == EPIPE);
    char buf;
    CHECK(recv(sockets[0], &buf, 1, 0) == 0);
    CHECK(close(sockets[0]) == 0);
}

static void pending_reset_so_error(void) {
    int sockets[2], error = 0;
    pair(sockets, 0);
    CHECK(send(sockets[0], "unread", 6, 0) == 6);
    CHECK(send(sockets[1], "reply", 5, 0) == 5);
    CHECK(close(sockets[1]) == 0);
    socklen_t size = sizeof(error);
    CHECK(getsockopt(sockets[0], SOL_SOCKET, SO_ERROR, &error, &size) == 0);
    CHECK(size == sizeof(error) && error == ECONNRESET);
    CHECK(getsockopt(sockets[0], SOL_SOCKET, SO_ERROR, &error, &size) == 0);
    CHECK(error == 0);
    char buf[16];
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 5 && memcmp(buf, "reply", 5) == 0);
    CHECK(recv(sockets[0], buf, sizeof(buf), 0) == 0);
    CHECK(close(sockets[0]) == 0);
}

static void readv_unused_tail(void) {
    int sockets[2];
    unsigned char first[4], second[8];
    memset(first, 0xa5, sizeof(first));
    memset(second, 0xa5, sizeof(second));
    struct iovec iov[] = {{.iov_base = first, .iov_len = sizeof(first)},
                          {.iov_base = second, .iov_len = sizeof(second)}};
    pair(sockets, 0);
    CHECK(send(sockets[0], "abcdef", 6, 0) == 6);
    CHECK(readv(sockets[1], iov, 2) == 6);
    CHECK(memcmp(first, "abcd", 4) == 0 && memcmp(second, "ef", 2) == 0);
    for (size_t i = 2; i < sizeof(second); i++) CHECK(second[i] == 0xa5);
    close_pair(sockets);
}

static void positional_io_espipe(void) {
    int sockets[2];
    char buf;
    pair(sockets, 0);
    CHECK(lseek(sockets[0], 0, SEEK_SET) == -1 && errno == ESPIPE);
    CHECK(pread(sockets[0], &buf, 1, 0) == -1 && errno == ESPIPE);
    CHECK(pwrite(sockets[0], "x", 1, 0) == -1 && errno == ESPIPE);
    close_pair(sockets);
}

static void fionread_listener_einval(void) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strcpy(address.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    int listener = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(listener >= 0);
    CHECK(bind(listener, (struct sockaddr *)&address, size) == 0 && listen(listener, 1) == 0);
    int available = -1;
    CHECK(ioctl(listener, FIONREAD, &available) == -1 && errno == EINVAL);
    CHECK(close(listener) == 0 && unlink(socket_path) == 0);
}

static void backlog_expansion_wakeup(void) {
    struct sockaddr_un address = {.sun_family = AF_UNIX};
    strcpy(address.sun_path, socket_path);
    socklen_t size = (socklen_t)(offsetof(struct sockaddr_un, sun_path) + strlen(socket_path) + 1);
    int listener = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(listener >= 0 && bind(listener, (struct sockaddr *)&address, size) == 0);
    CHECK(listen(listener, 0) == 0);
    int first = socket(AF_UNIX, SOCK_SEQPACKET, 0);
    CHECK(first >= 0 && connect(first, (struct sockaddr *)&address, size) == 0);
    int sync_pipe[2];
    CHECK(pipe(sync_pipe) == 0);
    pid_t child = fork();
    CHECK(child >= 0);
    if (child == 0) {
        alarm(10);
        CHECK(close(listener) == 0 && close(first) == 0 && close(sync_pipe[0]) == 0);
        int client = socket(AF_UNIX, SOCK_SEQPACKET, 0);
        CHECK(client >= 0);
        CHECK(write(sync_pipe[1], "r", 1) == 1);
        CHECK(connect(client, (struct sockaddr *)&address, size) == 0);
        CHECK(send(client, "expanded", 8, 0) == 8);
        CHECK(write(sync_pipe[1], "d", 1) == 1);
        CHECK(close(client) == 0 && close(sync_pipe[1]) == 0);
        _exit(0);
    }
    CHECK(close(sync_pipe[1]) == 0);
    char buf[16];
    CHECK(read(sync_pipe[0], buf, 1) == 1 && buf[0] == 'r');
    CHECK(usleep(50000) == 0);
    int status;
    CHECK(waitpid(child, &status, WNOHANG) == 0);
    CHECK(listen(listener, 2) == 0);
    struct pollfd pfd = {.fd = sync_pipe[0], .events = POLLIN};
    CHECK(poll(&pfd, 1, 5000) == 1 && (pfd.revents & POLLIN) != 0);
    CHECK(read(sync_pipe[0], buf, 1) == 1 && buf[0] == 'd');
    int accepted_first = accept(listener, NULL, NULL);
    CHECK(accepted_first >= 0);
    int accepted_second = accept(listener, NULL, NULL);
    CHECK(accepted_second >= 0);
    CHECK(recv(accepted_second, buf, sizeof(buf), 0) == 8 && memcmp(buf, "expanded", 8) == 0);
    CHECK(waitpid(child, &status, 0) == child);
    CHECK(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    CHECK(close(accepted_first) == 0 && close(accepted_second) == 0 && close(first) == 0);
    CHECK(close(listener) == 0 && close(sync_pipe[0]) == 0 && unlink(socket_path) == 0);
}

struct test_case { const char *name; void (*run)(void); };
static const struct test_case cases[] = {
    {"socketpair-flags", socketpair_flags},
    {"raw-socketpair-flags", raw_socketpair_flags},
    {"record-boundaries", record_boundaries},
    {"peek-and-truncation", peek_and_truncation},
    {"input-msg-trunc", input_msg_trunc},
    {"scatter-gather-record", scatter_gather_record},
    {"vectored-io-record", vectored_io_record},
    {"waitall-record-boundary", waitall_record_boundary},
    {"zero-length-record", zero_length_record},
    {"close-eof", close_eof},
    {"shutdown-half-close", shutdown_half_close},
    {"nonblocking-poll-select", nonblocking_poll_select},
    {"bounded-backpressure", bounded_backpressure},
    {"blocking-poll-wakeup", blocking_poll_wakeup},
    {"rights-transfer", rights_transfer},
    {"rights-cloexec", rights_cloexec},
    {"rights-peek", rights_peek},
    {"rights-control-truncation", rights_control_truncation},
    {"rights-no-control-buffer", rights_no_control_buffer},
    {"rights-discarded-by-read", rights_discarded_by_read},
    {"peer-credentials", peer_credentials},
    {"message-credentials", message_credentials},
    {"pathname-connection", pathname_connection},
    {"fork-transfer", fork_transfer},
    {"abstract-names", abstract_names},
    {"accept-default-flags", accept_default_flags},
    {"cloexec-eof", cloexec_eof},
    {"seqpacket-sigpipe-behavior", seqpacket_sigpipe_behavior},
    {"blocking-receive-wakeup", blocking_receive_wakeup},
    {"shutdown-read-queued", shutdown_read_queued},
    {"zero-data-rights", zero_data_rights},
    {"fionread-queued-bytes", fionread_queued_bytes},
    {"receive-timeout", receive_timeout},
    {"send-timeout", send_timeout},
    {"listener-full-connect-wakeup", listener_full_connect_wakeup},
    {"noncyclic-socket-rights", noncyclic_socket_rights},
    {"close-unread-reset", close_unread_reset},
    {"raw-time64-options", raw_time64_options},
    {"sendto-connected-destination", sendto_connected_destination},
    {"recvfrom-unnamed-sender", recvfrom_unnamed_sender},
    {"pending-reset-send", pending_reset_send},
    {"pending-reset-so-error", pending_reset_so_error},
    {"readv-unused-tail", readv_unused_tail},
    {"positional-io-espipe", positional_io_espipe},
    {"fionread-listener-einval", fionread_listener_einval},
    {"backlog-expansion-wakeup", backlog_expansion_wakeup},
};

static void timeout_parent(int signal_number) {
    (void)signal_number;
    static const char message[] = "FAIL suite timeout\n";
    (void)write(STDERR_FILENO, message, sizeof(message) - 1);
    if (active_child > 0) (void)kill(active_child, SIGKILL);
    _exit(124);
}

int main(int argc, char **argv) {
    setvbuf(stdout, NULL, _IONBF, 0);
    executable_path = argv[0];
    if (argc == 3 && strcmp(argv[1], "--exec-check-closed") == 0) {
        current_test = "cloexec-eof after exec";
        char *end;
        long descriptor = strtol(argv[2], &end, 10);
        CHECK(*end == '\0' && descriptor >= 0 && descriptor <= 65535);
        CHECK(fcntl((int)descriptor, F_GETFD) == -1 && errno == EBADF);
        return 0;
    }
    if (argc > 2) {
        fprintf(stderr, "usage: %s [--list|test-name]\n", argv[0]);
        return 2;
    }
    if (argc == 2 && strcmp(argv[1], "--list") == 0) {
        for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) puts(cases[i].name);
        return 0;
    }
    int matching = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++)
        if (argc == 1 || strcmp(argv[1], cases[i].name) == 0) matching++;
    if (!matching) {
        fprintf(stderr, "unknown test: %s\n", argv[1]);
        return 2;
    }
    char directory[] = "/tmp/ish-seqpacket.XXXXXX";
    if (!mkdtemp(directory)) { perror("mkdtemp"); return 1; }
    int n = snprintf(socket_path, sizeof(socket_path), "%s/socket", directory);
    if (n < 0 || (size_t)n >= sizeof(socket_path)) { rmdir(directory); return 1; }
    struct sigaction sa = {.sa_handler = timeout_parent};
    sigemptyset(&sa.sa_mask);
    if (sigaction(SIGALRM, &sa, NULL) != 0) { perror("sigaction"); rmdir(directory); return 1; }
    alarm(240);
    int passed = 0, failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); i++) {
        if (argc == 2 && strcmp(argv[1], cases[i].name) != 0) continue;
        current_test = cases[i].name;
        printf("RUN %s\n", current_test);
        pid_t child = fork();
        if (child < 0) { perror("fork"); failures++; break; }
        if (child == 0) {
            signal(SIGALRM, SIG_DFL);
            alarm(15);
            cases[i].run();
            _exit(0);
        }
        active_child = child;
        int status = 0;
        pid_t waited;
        do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
        active_child = 0;
        if (waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0) {
            printf("PASS %s\n", current_test);
            passed++;
        } else {
            if (waited == child && WIFSIGNALED(status))
                printf("FAIL %s signal=%d\n", current_test, WTERMSIG(status));
            else printf("FAIL %s child-status=%d wait-result=%ld\n", current_test, status, (long)waited);
            failures++;
        }
        (void)unlink(socket_path);
    }
    alarm(0);
    (void)rmdir(directory);
    printf("RESULT passed=%d failed=%d selected=%d\n", passed, failures, matching);
    return failures ? 1 : 0;
}
