#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <ctype.h>

/*typedef uint8_t bool;
#define true 1
#define false 0*/

/////
// STRUCTURE FOR BPB(reserved sector w/o boot code)
////
typedef struct
{
    uint8_t BootjumpInstruction[3];
    uint8_t OemIdentifier[8];
    uint16_t bytes_per_sector;
    uint8_t sectors_per_cluster;
    uint16_t reserve_sectors;
    uint8_t fat_count;
    uint16_t dir_entry_count;
    uint16_t total_sector;
    uint8_t media_descriptor;
    uint16_t sectors_per_fat;
    uint16_t sectors_per_track;
    uint16_t heads;
    uint32_t hidden_sectors;
    uint32_t sector_count;
    uint8_t drive_number;
    uint8_t signature;
    uint8_t vol_id;
    uint8_t volume_label[11];
    uint8_t sys_id[8];

} __attribute__((packed)) bootsector;

/////
// STRUCTURE FOR DIRECTORY_ENTRY
////
typedef struct
{
    uint8_t name[11];
    uint8_t attributes;
    uint8_t reserved;
    uint8_t created_time_tenths;
    uint16_t created_time;
    uint16_t created_date;
    uint16_t accessed_date;
    uint16_t first_cluster_high;
    uint16_t modified_time;
    uint16_t modified_date;
    uint16_t first_cluster_low;
    uint32_t size;
} __attribute__((packed)) directory_entry;

bootsector bootsec;
uint8_t *general_boot_FAT = NULL;
directory_entry *root_dir = NULL;
uint8_t last_root_dir;

/// we divide implementation into 4 parts for now -
// 1) to read the BPB
// 2)To perform a general read
// 3)To copy the FAT (FAT #1) ( IMP : it does not read root directory, data region , FAT #2)
// 4)To read the root directory entries

// 1
bool read_BPB(FILE *disk)
{
    return fread(&bootsec, sizeof(bootsec), 1, disk) > 0;
}

// 2
bool general_sector_read(FILE *data, uint32_t lba, void *read_buffer, uint32_t count)
{
    // return fread(read_to,bytes_per_sector,count,data) == count
    bool check = true;
    check = check && (fseek(data, lba * bootsec.bytes_per_sector, SEEK_SET) == 0);
    check = check && (fread(read_buffer, bootsec.bytes_per_sector, count, data) == count);
    return check;
}

// 3
bool read_FAT(FILE *disk)
{
    general_boot_FAT = (uint8_t *)malloc(bootsec.sectors_per_fat * bootsec.bytes_per_sector);
    // IMP : the sector_per_fat etc starting counting sectors from after the reserved_sectors
    return general_sector_read(disk, bootsec.reserve_sectors, general_boot_FAT, bootsec.sectors_per_fat);
}

// 4
bool read_root_dir(FILE *disk)
{
    uint32_t lba = bootsec.reserve_sectors + bootsec.fat_count * bootsec.sectors_per_fat;
    uint32_t size = sizeof(directory_entry) * bootsec.dir_entry_count;
    // root_dir = (directory_entry*)malloc(size)
    // NOTICE the above lien is commented out as were doing a sector wise read '2)'
    // therefore we must fine the ceil of size/no of sectors
    uint32_t sectors = (size + bootsec.bytes_per_sector - 1) / bootsec.bytes_per_sector;
    last_root_dir = lba + sectors;
    root_dir = (directory_entry *)malloc(sectors * bootsec.bytes_per_sector); // minimum no of sectors we must read
    return general_sector_read(disk, lba, root_dir, sectors);
}

// CODE to find a file

directory_entry *find_file(const char *file_name)
{
    for (int i = 0; i < bootsec.dir_entry_count; i++)
    {
        if (memcmp(file_name, root_dir[i].name, 11) == 0)
        {
            return &root_dir[i];
        }
    }
    return NULL; // this is the assumption if the file is found
}

bool read_file(FILE *disk, directory_entry *s, uint8_t *output_buffer)
{
    uint16_t cluster_no = s->first_cluster_low;
    bool k = true;
    do
    {
        uint32_t lba = last_root_dir + (cluster_no - 2) * bootsec.sectors_per_cluster;       // convert cluster number to sector number
        k = k && general_sector_read(disk, lba, output_buffer, bootsec.sectors_per_cluster); // to read all the sectors from the specified cluster into our buffer
        output_buffer += bootsec.sectors_per_cluster * bootsec.bytes_per_sector;
        uint32_t bytes_cluster = (cluster_no * 12) / 8; // IMP : used to reinterpret clusters in terms of bytes
        if (cluster_no % 2 == 0)
        {
            cluster_no = *(uint16_t *)(general_boot_FAT + bytes_cluster) & 0x0FFF;
        }
        else
        {
            cluster_no = *(uint16_t *)(general_boot_FAT + bytes_cluster) >> 4;
        }
    } while (k && cluster_no < 0xFF8);
    return k;
}

int main(uint32_t argc, char **argv)
{
    if (argc < 3)
    {
        printf("The expected syntax is : %s <disk_image> <file_name>\n", argv[0]);
        return -1;
    }

    FILE *disk = fopen(argv[1], "rb");
    if (!disk)
    {
        fprintf(stderr, "Cannot open disk image %s!\n", argv[1]);
        return -1;
    }

    if (!read_BPB(disk))
    {
        fprintf(stderr, "Cannot read the BIOS parameter block and EBR\n");
        return -2;
    }

    if (!read_FAT(disk))
    {
        fprintf(stderr, "Cannot read the FAT#1\n");
        free(general_boot_FAT);
        return -3;
    }

    if (!read_root_dir(disk))
    {
        fprintf(stderr, "Cannot read the Root Directory\n");
        free(root_dir);
        free(general_boot_FAT);
        return -4;
    }
    directory_entry *file_entry = find_file(argv[2]);
    if (file_entry == NULL)
    {
        fprintf(stderr, "Cannot find the file in tthe root directory!");
        free(general_boot_FAT);
        free(root_dir);
        return -5;
    }
    uint8_t *output_buffer = (uint8_t *)malloc(file_entry->size + bootsec.bytes_per_sector);
    if (!read_file(disk, file_entry, output_buffer))
    {
        fprintf(stderr, "Unable to read file!");
        free(general_boot_FAT);
        free(root_dir);
        free(output_buffer);
        return -6;
    }

    for (int i = 0; i < file_entry->size; i++)
    {
        if (isprint(output_buffer[i]))
            fputc(output_buffer[i], stdout);
        else
            printf("%02x", output_buffer[i]);
    }
    printf("\n");
    return 0;
}