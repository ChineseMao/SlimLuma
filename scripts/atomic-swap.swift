import Darwin
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: atomic-swap.swift <first-path> <second-path>\n", stderr)
    exit(EX_USAGE)
}

let firstPath = CommandLine.arguments[1]
let secondPath = CommandLine.arguments[2]

let result = firstPath.withCString { firstPointer in
    secondPath.withCString { secondPointer in
        renameatx_np(
            AT_FDCWD,
            firstPointer,
            AT_FDCWD,
            secondPointer,
            UInt32(RENAME_SWAP)
        )
    }
}

guard result == 0 else {
    perror("renameatx_np(RENAME_SWAP)")
    exit(EX_OSERR)
}
