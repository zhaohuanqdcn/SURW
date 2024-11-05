import os
import random

pasv_commands = ['LIST']
file_commands = ['MKD', 'MKD', 'MKD', 'RMD', 'RMD', 'RMD']
util_commands = ['PWD', 'TYPE I', 'SYST']


random.seed(os.getenv("RANDOM_SEED"))

def generate_ftp_commands(idx):
    
    next_mkd = 0
    next_rmd = 0
    rmd_idx = idx + 1 if idx + 1 <= 4 else 1

    filename = f'test{idx}.in'
    commands = [
        f"USER test{idx}",
        f"PASS test"
    ]

    cmd = []
    cmd.extend(file_commands)
    cmd.extend(util_commands)    
    random.shuffle(cmd)

    for c in cmd:
        if c == 'MKD':
            next_mkd += 1
            commands.append(f'{c} {idx}-{next_mkd}')
        elif c == 'RMD':
            next_rmd += 1
            commands.append(f'{c} {rmd_idx}-{next_rmd}')
        else:
            commands.append(c)
    
    commands.append('PASV')
    commands.append('LIST')    
    commands.append('QUIT')
    commands.append('')
    
    with open(filename, 'w') as file:
        file.write('\r\n'.join(commands))

for i in range(1, 5):
    generate_ftp_commands(i)
